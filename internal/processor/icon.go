package processor

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"io"
)

// icnsPNGTypes maps ICNS image types that carry PNG-compressed icon data to
// their nominal edge length in pixels.
var icnsPNGTypes = map[string]int{
	"icp4": 16, "icp5": 32, "icp6": 64,
	"ic07": 128, "ic08": 256, "ic09": 512, "ic10": 1024,
	"ic11": 32, "ic12": 64, "ic13": 256, "ic14": 512,
}

// icnsARGBTypes maps raw big-endian ARGB raster icon types to their size.
var icnsARGBTypes = map[string]int{
	"ic04": 16,
	"ic05": 32,
}

// icnsRGBTypes maps 24-bit RGB raster icon types to their size. These carry no
// alpha channel themselves; transparency comes from a companion 8-bit mask
// chunk (see icnsMaskTypes).
var icnsRGBTypes = map[string]int{
	"is32": 16,
	"il32": 32,
	"ih32": 48,
	"it32": 128,
}

// icnsMaskTypes maps 8-bit alpha mask chunks to the size they apply to.
var icnsMaskTypes = map[string]int{
	"s8mk": 16,
	"l8mk": 32,
	"h8mk": 48,
	"t8mk": 128,
}

func init() {
	// Register the ICNS container so image.Decode magically recognises .icns
	// uploads by signature, alongside the existing HEIC registration.
	image.RegisterFormat("icns", "icns", DecodeIcns, DecodeIcnsConfig)
}

// DecodeIcns decodes the highest-resolution representation present in an Apple
// Icon Image (.icns) container, preferring entries that carry an alpha channel
// so transparent backgrounds survive the conversion.
func DecodeIcns(r io.Reader) (image.Image, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return nil, fmt.Errorf("failed to read ICNS data: %w", err)
	}
	return decodeIcns(data)
}

// DecodeIcnsConfig returns the config of the best available representation.
func DecodeIcnsConfig(r io.Reader) (image.Config, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return image.Config{}, fmt.Errorf("failed to read ICNS data: %w", err)
	}

	img, err := decodeIcns(data)
	if err != nil {
		return image.Config{}, err
	}
	bounds := img.Bounds()
	return image.Config{
		ColorModel: img.ColorModel(),
		Width:      bounds.Dx(),
		Height:     bounds.Dy(),
	}, nil
}

// pngIconChunk is a PNG-compressed payload for the nominal edge length nominal.
type pngIconChunk struct {
	nominal int
	payload []byte
}

// decodeIcns parses the ICNS chunk table ([4-byte type][4-byte BE length][data]),
// decodes every supported representation and returns the "best" one: largest,
// with alpha preferred over an equally large opaque entry.
func decodeIcns(data []byte) (image.Image, error) {
	if len(data) < 8 || !bytes.Equal(data[:4], []byte("icns")) {
		return nil, fmt.Errorf("invalid ICNS file: bad magic")
	}

	var pngs []pngIconChunk
	var argb []icnsARGBChunk
	var rgb []icnsRGBChunk
	masks := make(map[int][]byte)

	i := 8
	for i+8 <= len(data) {
		typ := string(data[i : i+4])
		size := int(binary.BigEndian.Uint32(data[i+4 : i+8]))
		i += 8

		if size < 8 || i+size-8 > len(data) {
			break
		}
		payload := data[i : i+size-8]

		if nominal, ok := icnsPNGTypes[typ]; ok {
			pngs = append(pngs, pngIconChunk{nominal, payload})
		} else if nominal, ok := icnsARGBTypes[typ]; ok {
			argb = append(argb, icnsARGBChunk{nominal, payload})
		} else if nominal, ok := icnsMaskTypes[typ]; ok {
			masks[nominal] = payload
		} else if nominal, ok := icnsRGBTypes[typ]; ok {
			rgb = append(rgb, icnsRGBChunk{nominal, payload})
		}

		i += size - 8
	}

	// Score: larger size wins; for equal size prefer alpha-carrying entries.
	bestScore := -1
	var best image.Image

	consider := func(img image.Image, nominal int, hasAlpha bool) {
		score := nominal*2 - 1
		if hasAlpha {
			score++
		}
		if score <= bestScore {
			return
		}
		bestScore = score
		best = img
	}

	for _, c := range pngs {
		img, err := png.Decode(bytes.NewReader(c.payload))
		if err != nil {
			continue
		}
		consider(img, c.nominal, pngHasAlpha(c.payload))
	}
	for _, c := range argb {
		img, err := decodeARGB(c.nominal, c.payload)
		if err != nil {
			continue
		}
		consider(img, c.nominal, true)
	}
	for _, c := range rgb {
		img, err := decodeRGBMask(c.nominal, c.payload, masks[c.nominal])
		if err != nil {
			continue
		}
		consider(img, c.nominal, masks[c.nominal] != nil)
	}

	if best == nil {
		return nil, fmt.Errorf("unsupported ICNS: no decodable icon data found")
	}
	return best, nil
}

// pngHasAlpha reports whether a PNG stream has an alpha channel, derived from
// its IHDR color type (bit 2 set = 4 or 6). Offset 25 is the color type byte.
func pngHasAlpha(payload []byte) bool {
	if len(payload) < 26 {
		return false
	}
	return payload[25]&0x04 != 0
}

// icnsARGBChunk holds a raw big-endian ARGB raster (ic04/ic05).
type icnsARGBChunk struct {
	nominal int
	payload []byte
}

// decodeARGB converts big-endian ARGB pixel data (top-left first) to an image.
func decodeARGB(size int, payload []byte) (image.Image, error) {
	if size <= 0 || len(payload) < size*size*4 {
		return nil, fmt.Errorf("truncated ARGB icon data")
	}
	img := image.NewNRGBA(image.Rect(0, 0, size, size))
	for row := 0; row < size; row++ {
		base := row * size * 4
		for col := 0; col < size; col++ {
			o := base + col*4
			img.SetNRGBA(col, row, color.NRGBA{
				A: payload[o],
				R: payload[o+1],
				G: payload[o+2],
				B: payload[o+3],
			})
		}
	}
	return img, nil
}

// icnsRGBChunk holds a 24-bit RGB raster (is32/il32/ih32/it32).
type icnsRGBChunk struct {
	nominal int
	payload []byte
}

// decodeRGBMask composes 24-bit RGB pixel data with its companion 8-bit alpha
// mask into an RGBA image. Rows are 4-byte aligned, which the standard sizes
// already satisfy. When no mask chunk is present the image is opaque.
func decodeRGBMask(size int, payload, mask []byte) (image.Image, error) {
	if size <= 0 || len(payload) < size*size*3 {
		return nil, fmt.Errorf("truncated RGB icon data")
	}
	hasMask := len(mask) >= size*size
	img := image.NewNRGBA(image.Rect(0, 0, size, size))
	for row := 0; row < size; row++ {
		o := row * size * 3
		mo := row * size
		for col := 0; col < size; col++ {
			p := o + col*3
			a := byte(255)
			if hasMask {
				a = mask[mo+col]
			}
			img.SetNRGBA(col, row, color.NRGBA{
				A: a,
				R: payload[p],
				G: payload[p+1],
				B: payload[p+2],
			})
		}
	}
	return img, nil
}

// icoHeaderLen is the ICO container header (ICONDIR 6 bytes + single-entry
// ICONDIRENTRY 16 bytes) before the bitmap resource.
const icoHeaderLen = 6 + 16

// encodeICO writes an image as a single-frame Windows .ico. Icons up to 256px
// use the classic 32-bit BMP resource (universally supported); larger images use
// a PNG-compressed entry, the Vista+ representation, so a 512/1024px source does
// not balloon into a multi-megabyte bitmap.
func encodeICO(w io.Writer, img image.Image, quality int) error {
	bounds := img.Bounds()
	width := bounds.Dx()
	height := bounds.Dy()
	if width < 1 || height < 1 {
		return fmt.Errorf("invalid image size for ICO: %dx%d", width, height)
	}

	if width > 256 || height > 256 {
		return encodeICOPNG(w, img)
	}
	return encodeICOBMP(w, img)
}

// iconDirEntry writes the ICONDIR prefix plus a single ICONDIRENTRY.
func iconDirEntry(buf *bytes.Buffer, width, height int, resourceLen int) {
	_ = binary.Write(buf, binary.LittleEndian, uint16(0)) // reserved
	_ = binary.Write(buf, binary.LittleEndian, uint16(1)) // type: icon
	_ = binary.Write(buf, binary.LittleEndian, uint16(1)) // image count

	entryWidth := byte(width)
	if width >= 256 {
		entryWidth = 0
	}
	entryHeight := byte(height)
	if height >= 256 {
		entryHeight = 0
	}
	buf.WriteByte(entryWidth)                              // width (0 = 256)
	buf.WriteByte(entryHeight)                             // height (0 = 256)
	buf.WriteByte(0)                                       // color count (0 = 256)
	buf.WriteByte(0)                                       // reserved
	_ = binary.Write(buf, binary.LittleEndian, uint16(1))  // planes
	_ = binary.Write(buf, binary.LittleEndian, uint16(32)) // bit count
	_ = binary.Write(buf, binary.LittleEndian, uint32(resourceLen))
	_ = binary.Write(buf, binary.LittleEndian, uint32(icoHeaderLen))
}

// encodeICOBMP writes a classic 32-bit BGRA bitmap resource.
func encodeICOBMP(w io.Writer, img image.Image) error {
	bounds := img.Bounds()
	width := bounds.Dx()
	height := bounds.Dy()

	rgba := image.NewNRGBA(image.Rect(0, 0, width, height))
	draw.Draw(rgba, rgba.Bounds(), img, bounds.Min, draw.Src)

	pixelDataLen := width * height * 4

	var buf bytes.Buffer
	iconDirEntry(&buf, width, height, 40+pixelDataLen)

	// BITMAPINFOHEADER (no file header in an ICO resource)
	_ = binary.Write(&buf, binary.LittleEndian, uint32(40))
	_ = binary.Write(&buf, binary.LittleEndian, int32(width))
	_ = binary.Write(&buf, binary.LittleEndian, int32(height*2)) // XOR + AND planes
	_ = binary.Write(&buf, binary.LittleEndian, uint16(1))       // planes
	_ = binary.Write(&buf, binary.LittleEndian, uint16(32))      // bit count
	_ = binary.Write(&buf, binary.LittleEndian, uint32(0))       // BI_RGB
	_ = binary.Write(&buf, binary.LittleEndian, uint32(pixelDataLen))
	_ = binary.Write(&buf, binary.LittleEndian, int32(0))
	_ = binary.Write(&buf, binary.LittleEndian, int32(0))
	_ = binary.Write(&buf, binary.LittleEndian, uint32(0))
	_ = binary.Write(&buf, binary.LittleEndian, uint32(0))

	// Pixel data: bottom-up BGRA rows.
	pix := rgba.Pix
	stride := rgba.Stride
	rowBytes := width * 4
	for y := height - 1; y >= 0; y-- {
		row := pix[y*stride : y*stride+rowBytes]
		for x := 0; x < width; x++ {
			o := x * 4
			buf.Write([]byte{row[o+2], row[o+1], row[o], row[o+3]})
		}
	}

	_, err := w.Write(buf.Bytes())
	return err
}

// encodeICOPNG writes a PNG-compressed icon entry (Vista+), as used for large
// icon sizes; the resource is a plain PNG stream.
func encodeICOPNG(w io.Writer, img image.Image) error {
	var pngBuf bytes.Buffer
	if err := png.Encode(&pngBuf, img); err != nil {
		return fmt.Errorf("failed to encode ICO PNG resource: %w", err)
	}

	var buf bytes.Buffer
	bounds := img.Bounds()
	iconDirEntry(&buf, bounds.Dx(), bounds.Dy(), pngBuf.Len())
	buf.Write(pngBuf.Bytes())

	_, err := w.Write(buf.Bytes())
	return err
}
