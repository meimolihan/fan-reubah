//go:build nolibheif

package processor

import (
	"fmt"
	"image"
	"io"
)

// registerHeic is a no-op when libheif is excluded from the build.
func registerHeic() {}

// DecodeHeic is unavailable in builds compiled with the "nolibheif" tag.
func DecodeHeic(r io.Reader) (image.Image, error) {
	return nil, fmt.Errorf("HEIC/HEIF decoding is not available in this build (compiled without libheif)")
}

// encodeHEIC is unavailable in builds compiled with the "nolibheif" tag.
func encodeHEIC(w io.Writer, img image.Image, quality int) error {
	return fmt.Errorf("HEIC/HEIF encoding is not available in this build (compiled without libheif)")
}
