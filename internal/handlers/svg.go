package handlers

import (
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/meimolihan/fan-reubah/internal/constants"
	"github.com/meimolihan/fan-reubah/internal/processor"
	"github.com/meimolihan/fan-reubah/pkg/errors"
)

// ConvertToSVG vectorizes an uploaded raster image into an SVG document using
// the bundled vtracer conversion engine.
func ConvertToSVG(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseMultipartForm(constants.MaxFileSize); err != nil {
		errors.SendError(w, errors.New(errors.ErrInvalidFormat, "Unable to parse form", err))
		return
	}

	file, header, err := r.FormFile("image")
	if err != nil {
		errors.SendError(w, errors.New(errors.ErrInvalidFormat, "No file uploaded", err))
		return
	}
	defer file.Close()

	if header.Size > constants.MaxFileSize {
		errors.SendError(w, errors.New(errors.ErrInvalidSize, "File size exceeds 32MB limit", nil))
		return
	}

	tmpDir, err := os.MkdirTemp("", "fan-reubah-svg-*")
	if err != nil {
		errors.SendError(w, errors.New(errors.ErrProcessingFailed, "Failed to create temporary directory", err))
		return
	}
	defer os.RemoveAll(tmpDir)

	inputPath := filepath.Join(tmpDir, "input"+svgInputExtension(header))
	dst, err := os.Create(inputPath)
	if err != nil {
		errors.SendError(w, errors.New(errors.ErrProcessingFailed, "Failed to write uploaded file", err))
		return
	}
	if _, err := io.Copy(dst, file); err != nil {
		dst.Close()
		errors.SendError(w, errors.New(errors.ErrProcessingFailed, "Failed to write uploaded file", err))
		return
	}
	dst.Close()

	svg, err := processor.ConvertImageToSVG(inputPath, svgVectorOptions(r))
	if err != nil {
		if strings.Contains(err.Error(), "vtracer binary not found") {
			errors.SendError(w, errors.New(errors.ErrSVGConversion, "SVG converter is not available", err))
			return
		}
		errors.SendError(w, errors.New(errors.ErrSVGConversion, "SVG conversion failed", err))
		return
	}

	// Serve the generated SVG document as a downloadable attachment.
	w.Header().Set("Content-Type", "image/svg+xml")
	w.Header().Set("Content-Disposition", `attachment; filename="vectorized.svg"`)
	w.Write(svg)
}

// svgVectorOptions collects the vectorization parameters from the form. Empty
// values leave the corresponding vtracer option unset, letting a selected
// preset keep its tuned defaults.
func svgVectorOptions(r *http.Request) processor.SVGVectorOptions {
	value := r.FormValue
	return processor.SVGVectorOptions{
		Preset:          value("preset"),
		Hierarchical:    value("hierarchical"),
		Mode:            value("mode"),
		FilterSpeckle:   value("filterSpeckle"),
		ColorPrecision:  value("colorPrecision"),
		GradientStep:    value("gradientStep"),
		Simplify:        value("simplify"),
		MaxColors:       value("maxColors"),
		Optimize:        value("optimize"),
		PathPrecision:   value("pathPrecision"),
		Threshold:       value("threshold"),
		WatershedDetail: value("watershedDetail"),
		Adaptive:        value("adaptive") == "true",
	}
}

// svgInputExtension whitelists extensions the vtracer image decoder supports;
// anything else falls back to the generic png decoder path.
func svgInputExtension(header *multipart.FileHeader) string {
	ext := strings.ToLower(filepath.Ext(header.Filename))
	switch ext {
	case ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp",
		".tif", ".tiff", ".ico", ".pnm", ".pbm", ".pgm", ".ppm", ".pam",
		".tga", ".qoi":
		return ext
	}
	return ".png"
}