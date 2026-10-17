package processor

import (
	"bytes"
	"fmt"
	"image"
	"image/gif"
	_ "image/gif"
	"image/jpeg"
	_ "image/jpeg"
	"image/png"
	_ "image/png"
	"io"
	"math"

	"github.com/disintegration/imaging"
	"github.com/jung-kurt/gofpdf"
	"github.com/meimolihan/fan-reubah/internal/processor/background"
	"github.com/meimolihan/fan-reubah/internal/processor/optimize"
	"github.com/meimolihan/fan-reubah/internal/processor/resize"
	"golang.org/x/image/bmp"
)

func init() {
	// Register the HEIC/HEIF decoder when libheif is linked.
	// The implementation lives in heif_cgo.go (!nolibheif build) or is a no-op
	// stub in heif_stub.go (nolibheif build).
	registerHeic()
}

// ProcessOptions defines the options for image processing
type ProcessOptions struct {
	Width            int
	Height           int
	ResizeMode       resize.ResizeMode
	OutputFormat     string
	Quality          int
	RemoveBackground bool
	OptimizeImage    bool
}

type Config struct {
	DefaultQuality int
	DefaultFormat  string
}

type ImageProcessor struct {
	config Config
}

func NewImageProcessor() *ImageProcessor {
	return &ImageProcessor{
		config: Config{
			DefaultQuality: 85,
			DefaultFormat:  "jpeg",
		},
	}
}

func (p *ImageProcessor) ProcessImageData(img image.Image, opts ProcessOptions) (*ProcessedImage, error) {
	// Set default format and validate
	if opts.OutputFormat == "" {
		opts.OutputFormat = p.config.DefaultFormat
	}
	// Removing the background produces transparency, which JPEG/BMP/GIF would
	// flatten away; route those through PNG instead.
	if opts.RemoveBackground && !supportsAlpha(opts.OutputFormat) {
		opts.OutputFormat = "png"
	}
	if !isValidFormat(opts.OutputFormat) {
		return nil, fmt.Errorf("unsupported format: %s", opts.OutputFormat)
	}

	var err error
	// Remove background if requested
	if opts.RemoveBackground {
		img, err = background.RemoveBackground(img)
		if err != nil {
			return nil, fmt.Errorf("failed to remove background: %w", err)
		}
	}

	// Resize if needed
	if opts.Width > 0 || opts.Height > 0 {
		img, err = resize.Resize(img, resize.ResizeOptions{
			Width:  opts.Width,
			Height: opts.Height,
			Mode:   opts.ResizeMode,
			Filter: imaging.Lanczos,
		})
		if err != nil {
			return nil, fmt.Errorf("failed to resize image: %w", err)
		}
	}

	// Add optimization step
	if opts.OptimizeImage {
		optimizeOpts := optimize.GetOptionsForQuality(opts.OutputFormat,
			optimize.QualityLevel(getQualityLevel(opts.Quality)))
		var buf bytes.Buffer
		if err := optimize.Optimize(&buf, img, opts.OutputFormat, optimizeOpts); err != nil {
			return nil, fmt.Errorf("failed to optimize image: %w", err)
		}
		// Decode the optimized image
		img, _, err = image.Decode(&buf)
		if err != nil {
			return nil, fmt.Errorf("failed to decode optimized image: %w", err)
		}
	}

	return &ProcessedImage{
		Image:   img,
		Format:  opts.OutputFormat,
		Quality: opts.Quality,
	}, nil
}

type ProcessedImage struct {
	Image   image.Image
	Format  string
	Quality int
}

func (pi *ProcessedImage) Write(w io.Writer) error {
	switch pi.Format {
	case "jpeg", "jpg":
		return jpeg.Encode(w, pi.Image, &jpeg.Options{Quality: pi.Quality})
	case "png":
		encoder := &png.Encoder{
			CompressionLevel: png.CompressionLevel((pi.Quality * 9) / 100),
		}
		return encoder.Encode(w, pi.Image)
	case "webp":
		return encodeWebP(w, pi.Image, pi.Quality)
	case "gif":
		return gif.Encode(w, pi.Image, &gif.Options{
			NumColors: (pi.Quality * 256) / 100,
		})
	case "bmp":
		return bmp.Encode(w, pi.Image)
	case "ico":
		return encodeICO(w, pi.Image, pi.Quality)
	case "heic", "heif":
		return encodeHEIC(w, pi.Image, pi.Quality)
	case "pdf":
		return convertToPDF(w, pi.Image, pi.Quality)
	default:
		return fmt.Errorf("unsupported format for writing: %s", pi.Format)
	}
}

func isValidFormat(format string) bool {
	validFormats := map[string]bool{
		"jpeg": true,
		"jpg":  true,
		"png":  true,
		"webp": true,
		"gif":  true,
		"bmp":  true,
		"ico":  true,
		"heic": true,
		"heif": true,
		"pdf":  true,
	}
	return validFormats[format]
}

// supportsAlpha reports whether an output format preserves an alpha channel.
func supportsAlpha(format string) bool {
	switch format {
	case "png", "webp", "ico", "heic", "heif":
		return true
	default:
		return false
	}
}

func getQualityLevel(quality int) string {
	switch {
	case quality <= 60:
		return "low"
	case quality <= 75:
		return "medium"
	case quality <= 90:
		return "high"
	default:
		return "lossless"
	}
}

func convertToPDF(w io.Writer, img image.Image, quality int) error {
	// Create a new PDF
	pdf := gofpdf.New("P", "mm", "A4", "")
	pdf.AddPage()

	// Convert image to JPEG bytes for embedding
	var jpegBuf bytes.Buffer
	if err := jpeg.Encode(&jpegBuf, img, &jpeg.Options{Quality: quality}); err != nil {
		return fmt.Errorf("failed to encode image for PDF: %w", err)
	}

	// Get image dimensions
	bounds := img.Bounds()
	imgWidth := float64(bounds.Dx())
	imgHeight := float64(bounds.Dy())

	// Calculate scaling to fit on A4 page (210x297mm)
	pageWidth := 210.0
	pageHeight := 297.0
	margin := 10.0
	maxWidth := pageWidth - (2 * margin)
	maxHeight := pageHeight - (2 * margin)

	// Calculate scale to fit within margins while maintaining aspect ratio
	scale := math.Min(maxWidth/imgWidth, maxHeight/imgHeight)
	finalWidth := imgWidth * scale
	finalHeight := imgHeight * scale

	// Center the image on the page
	x := (pageWidth - finalWidth) / 2
	y := (pageHeight - finalHeight) / 2

	// Add the image to PDF
	pdf.RegisterImageOptionsReader("image", gofpdf.ImageOptions{ImageType: "JPEG"}, &jpegBuf)
	pdf.Image("image", x, y, finalWidth, finalHeight, false, "", 0, "")

	// Write PDF to output
	return pdf.Output(w)
}
