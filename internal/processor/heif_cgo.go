//go:build !nolibheif

package processor

import (
	"bytes"
	"fmt"
	"image"
	"image/jpeg"
	"image/png"
	"io"
	"os"
	"path/filepath"

	"github.com/MaestroError/go-libheif"
)

// registerHeic registers the HEIC/HEIF decoder. Compiled only when libheif is
// linked (the default build and any build without the "nolibheif" tag).
func registerHeic() {
	image.RegisterFormat("heic", "ftypheic", DecodeHeic, nil)
	image.RegisterFormat("heif", "ftypheif", DecodeHeic, nil)
	image.RegisterFormat("heic", "ftypmif1", DecodeHeic, nil) // For HEIF images from iOS
	image.RegisterFormat("heic", "ftypmsf1", DecodeHeic, nil) // For HEIF images from iOS
}

// DecodeHeic decodes HEIC/HEIF images
func DecodeHeic(r io.Reader) (image.Image, error) {
	// Create temporary file for the HEIC data
	tmpDir := os.TempDir()
	tmpHEIC := filepath.Join(tmpDir, "temp_input.heic")
	defer os.Remove(tmpHEIC)

	// Create temporary file
	f, err := os.Create(tmpHEIC)
	if err != nil {
		return nil, fmt.Errorf("failed to create temporary HEIC file: %w", err)
	}
	defer f.Close()

	// Copy the reader data to the temp file
	if _, err := io.Copy(f, r); err != nil {
		return nil, fmt.Errorf("failed to write HEIC data: %w", err)
	}

	// Create temporary file for JPEG output
	tmpJPG := filepath.Join(tmpDir, "temp_output.jpg")
	defer os.Remove(tmpJPG)

	// Convert HEIC to JPEG
	if err := libheif.HeifToJpeg(tmpHEIC, tmpJPG, 100); err != nil {
		return nil, fmt.Errorf("failed to convert HEIC to JPEG: %w", err)
	}

	// Read the JPEG file
	jpegData, err := os.ReadFile(tmpJPG)
	if err != nil {
		return nil, fmt.Errorf("failed to read converted JPEG: %w", err)
	}

	// Decode the JPEG data
	return jpeg.Decode(bytes.NewReader(jpegData))
}

func encodeHEIC(w io.Writer, img image.Image, quality int) error {
	// Create temporary files for the conversion process
	tmpDir := os.TempDir()
	tmpPNG := filepath.Join(tmpDir, "temp.png")
	tmpHEIC := filepath.Join(tmpDir, "temp.heic")

	// Clean up temporary files when done
	defer os.Remove(tmpPNG)
	defer os.Remove(tmpHEIC)

	// Save image as PNG first
	pngFile, err := os.Create(tmpPNG)
	if err != nil {
		return fmt.Errorf("failed to create temporary PNG file: %w", err)
	}
	if err := png.Encode(pngFile, img); err != nil {
		pngFile.Close()
		return fmt.Errorf("failed to encode image to PNG: %w", err)
	}
	pngFile.Close()

	// Convert PNG to HEIC
	if err := libheif.ImageToHeif(tmpPNG, tmpHEIC); err != nil {
		return fmt.Errorf("failed to convert to HEIC: %w", err)
	}

	// Read the HEIC file and write to the output
	heicData, err := os.ReadFile(tmpHEIC)
	if err != nil {
		return fmt.Errorf("failed to read HEIC file: %w", err)
	}

	if _, err := w.Write(heicData); err != nil {
		return fmt.Errorf("failed to write HEIC data: %w", err)
	}

	return nil
}
