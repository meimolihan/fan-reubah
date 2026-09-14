package background

import (
	"bytes"
	"fmt"
	"image"
	"image/draw"
	"image/png"
	"os/exec"
	"sort"
)

// RemoveBackground strips the dominant background from an image and returns a
// copy carrying an alpha channel. It prefers the rembg CLI (U2-Net) when it is
// installed, and otherwise falls back to a self-contained, dependency-free
// border flood-fill heuristic that needs no model or network access.
func RemoveBackground(img image.Image) (image.Image, error) {
	if out, err := removeWithRembg(img); err == nil {
		return out, nil
	}
	return removeWithFloodFill(img), nil
}

// removeWithRembg shells out to the rembg command-line tool, streaming the
// source as PNG on stdin and reading the cut-out PNG from stdout.
func removeWithRembg(img image.Image) (image.Image, error) {
	if _, err := exec.LookPath("rembg"); err != nil {
		return nil, err
	}

	var inputBuf bytes.Buffer
	if err := png.Encode(&inputBuf, img); err != nil {
		return nil, fmt.Errorf("encode input for rembg: %w", err)
	}

	cmd := exec.Command("rembg", "i", "-", "-")
	cmd.Stdin = &inputBuf
	var outputBuf bytes.Buffer
	cmd.Stdout = &outputBuf
	cmd.Stderr = &outputBuf

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("rembg failed: %w", err)
	}

	result, err := png.Decode(bytes.NewReader(outputBuf.Bytes()))
	if err != nil {
		return nil, fmt.Errorf("decode rembg output: %w", err)
	}
	return result, nil
}

// removeWithFloodFill removes a photo's background by finding the dominant
// colour at the image borders and flood-filling inward from the edges within a
// similarity tolerance, punching those pixels out to full transparency. Edge
// pixels that sit between the background and the subject are feathered so the
// cut-out keeps soft anti-aliased contours.
func removeWithFloodFill(img image.Image) image.Image {
	bounds := img.Bounds()
	dst := image.NewNRGBA(image.Rect(0, 0, bounds.Dx(), bounds.Dy()))
	draw.Draw(dst, dst.Bounds(), img, bounds.Min, draw.Src)

	w, h := dst.Bounds().Dx(), dst.Bounds().Dy()
	if w < 3 || h < 3 {
		return dst
	}

	pix := dst.Pix
	stride := dst.Stride
	pixAt := func(x, y int) int { return y*stride + x*4 }

	// Width of the border band inspected for the background colour.
	band := w / 30
	if band > 24 {
		band = 24
	}
	if band < 2 {
		band = 2
	}

	// 1) Coarse 3-bit-per-channel histogram over the border band.
	const shift = 5
	var hist [1 << 9]int
	count := func(x, y int) {
		p := pixAt(x, y)
		hist[bucket(pix[p], pix[p+1], pix[p+2], shift)]++
	}
	for x := 0; x < w; x++ {
		for y := 0; y < band; y++ {
			count(x, y)
			count(x, h-1-y)
		}
	}
	for y := 0; y < h; y++ {
		for x := 0; x < band; x++ {
			count(x, y)
			count(w-1-x, y)
		}
	}

	maxCount, bgBucket := 0, 0
	for k, c := range hist {
		if c > maxCount {
			maxCount, bgBucket = c, k
		}
	}
	bgR := byte(bgBucket>>6) << shift
	bgG := byte((bgBucket>>3)&7) << shift
	bgB := byte(bgBucket&7) << shift

	// 2) Tolerance from the spread of border colours around the dominant one.
	// Solid backgrounds yield a tight spread; noisy/gradient ones a wider one.
	distances := make([]int, 0, w*band*4)
	collect := func(x, y int) {
		p := pixAt(x, y)
		distances = append(distances, colorDistSq(pix[p], pix[p+1], pix[p+2], bgR, bgG, bgB))
	}
	for x := 0; x < w; x++ {
		for y := 0; y < band; y++ {
			collect(x, y)
			collect(x, h-1-y)
		}
	}
	for y := 0; y < h; y++ {
		for x := 0; x < band; x++ {
			collect(x, y)
			collect(w-1-x, y)
		}
	}
	sort.Ints(distances)

	p90 := distances[(len(distances)*9)/10]
	tolSq := p90 * 4
	if tolSq < 24*24 {
		tolSq = 24 * 24
	}
	if tolSq > 90*90 {
		tolSq = 90 * 90
	}

	// 3) Flood fill outward from matching border pixels.
	cleared := make([]byte, w*h)
	queue := make([]int, 0, w*h/8)
	seed := func(sx, sy int) {
		if sx < 0 || sy < 0 || sx >= w || sy >= h {
			return
		}
		o := sy*w + sx
		if cleared[o] != 0 {
			return
		}
		p := pixAt(sx, sy)
		if colorDistSq(pix[p], pix[p+1], pix[p+2], bgR, bgG, bgB) <= tolSq {
			cleared[o] = 1
			queue = append(queue, o)
		}
	}
	for x := 0; x < w; x++ {
		for y := 0; y < band; y++ {
			seed(x, y)
			seed(x, h-1-y)
		}
	}
	for y := 0; y < h; y++ {
		for x := 0; x < band; x++ {
			seed(x, y)
			seed(w-1-x, y)
		}
	}

	var neighbors [4]int
	for head := 0; head < len(queue); head++ {
		o := queue[head]
		x, y := o%w, o/w
		n := 0
		if x > 0 {
			neighbors[n] = o - 1
			n++
		}
		if x < w-1 {
			neighbors[n] = o + 1
			n++
		}
		if y > 0 {
			neighbors[n] = o - w
			n++
		}
		if y < h-1 {
			neighbors[n] = o + w
			n++
		}
		for i := 0; i < n; i++ {
			no := neighbors[i]
			if cleared[no] != 0 {
				continue
			}
			p := no * 4
			if colorDistSq(pix[p], pix[p+1], pix[p+2], bgR, bgG, bgB) <= tolSq {
				cleared[no] = 1
				queue = append(queue, no)
			}
		}
	}

	// 4) Apply: fully clear flooded pixels; feather the fringe just outside.
	feather := make([]byte, w*h)
	for o := range cleared {
		if o >= w*h || cleared[o] != 0 {
			continue
		}
		x, y := o%w, o/w
		adjacent := (x > 0 && cleared[o-1] != 0) ||
			(x < w-1 && cleared[o+1] != 0) ||
			(y > 0 && cleared[o-w] != 0) ||
			(y < h-1 && cleared[o+w] != 0)
		if !adjacent {
			continue
		}
		p := o * 4
		if colorDistSq(pix[p], pix[p+1], pix[p+2], bgR, bgG, bgB) <= tolSq*2 {
			feather[o] = 1
		}
	}

	for o, c := range cleared {
		if o >= w*h {
			break
		}
		p := o * 4
		if c != 0 {
			pix[p+3] = 0
			continue
		}
		if feather[o] == 0 {
			continue
		}
		d := colorDistSq(pix[p], pix[p+1], pix[p+2], bgR, bgG, bgB)
		if d > tolSq*2 {
			continue
		}
		f := float64(tolSq*2-d) / float64(tolSq) // 1 at the cleared edge → 0 at 2×tol
		pix[p+3] = byte(float64(pix[p+3]) * (0.15 + 0.85*f))
	}

	return dst
}

// bucket returns the coarse colour histogram index for a pixel using the given
// per-channel shift (3 bits kept when shift=5).
func bucket(r, g, b byte, shift int) int {
	return int(r>>shift)<<6 | int(g>>shift)<<3 | int(b>>shift)
}

// colorDistSq returns the squared Euclidean RGB distance between two colours.
func colorDistSq(r, g, b, rr, gg, bb byte) int {
	dr := int(r) - int(rr)
	dg := int(g) - int(gg)
	db := int(b) - int(bb)
	return dr*dr + dg*dg + db*db
}
