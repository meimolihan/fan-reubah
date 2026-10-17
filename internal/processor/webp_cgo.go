//go:build !nowebp

package processor

import (
	"image"
	"io"

	"github.com/chai2010/webp"
)

// encodeWebP encodes the image as WebP using the bundled libwebp CGO bridge.
// Compiled only when libwebp is linked (the default build and any build without
// the "nowebp" tag).
func encodeWebP(w io.Writer, img image.Image, quality int) error {
	return webp.Encode(w, img, &webp.Options{
		Lossless: quality == 100,
		Quality:  float32(quality),
	})
}
