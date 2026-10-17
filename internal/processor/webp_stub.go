//go:build nowebp

package processor

import (
	"fmt"
	"image"
	"io"
)

// encodeWebP is unavailable in builds compiled with the "nowebp" tag. This lets
// the project produce a pure-Go binary (CGO_ENABLED=0) without the libwebp
// native bridge, at the cost of WebP output support.
func encodeWebP(w io.Writer, img image.Image, quality int) error {
	return fmt.Errorf("WebP encoding is not available in this build (compiled without libwebp/cgo)")
}
