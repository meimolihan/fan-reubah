package processor

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/meimolihan/fan-reubah/internal/assets"
)

// SVGTimeout bounds a single vtracer invocation. Large scans can take a while.
const SVGTimeout = 2 * time.Minute

// SVGVectorOptions mirrors the tunable subset of vtracer's CLI that the web
// frontend exposes. Empty scalar fields are simply not forwarded to vtracer,
// so presets keep their tuned defaults.
type SVGVectorOptions struct {
	Preset          string
	Hierarchical    string
	Mode            string
	FilterSpeckle   string
	ColorPrecision  string
	GradientStep    string
	Simplify        string
	MaxColors       string
	Optimize        string
	PathPrecision   string
	Threshold       string
	WatershedDetail string
	Adaptive        bool
}

// ResolveVTracer locates the vtracer engine. Priority: VTRACER_PATH env var,
// the embedded (built-in) engine, then a PATH lookup. The embedded engine is
// extracted once to a cache directory and reused across requests.
func ResolveVTracer() string {
	if p := os.Getenv("VTRACER_PATH"); p != "" {
		return p
	}
	if bin := assets.VtracerBinary(); len(bin) > 0 {
		vtracerOnce.Do(func() {
			vtracerPath, vtracerErr = extractVTracer(bin)
		})
		if vtracerErr == nil && vtracerPath != "" {
			return vtracerPath
		}
	}
	if p, err := exec.LookPath("vtracer"); err == nil {
		return p
	}
	return ""
}

var (
	vtracerOnce sync.Once
	vtracerPath string
	vtracerErr  error
)

// extractVTracer writes the embedded engine to disk and returns its path.
func extractVTracer(bin []byte) (string, error) {
	var dirs []string
	if c, err := os.UserCacheDir(); err == nil && c != "" {
		dirs = append(dirs, filepath.Join(c, "fan-reubah"))
	}
	dirs = append(dirs, "")

	var lastErr error
	for _, dir := range dirs {
		if dir == "" {
			tmp, err := os.MkdirTemp("", "fan-reubah-vtracer-*")
			if err != nil {
				lastErr = err
				continue
			}
			dir = tmp
		} else if err := os.MkdirAll(dir, 0o755); err != nil {
			lastErr = err
			continue
		}
		path := filepath.Join(dir, "vtracer")
		if info, err := os.Stat(path); err == nil && info.Size() == int64(len(bin)) {
			return path, nil
		}
		if err := writeEmbeddedBinary(bin, path); err == nil {
			return path, nil
		} else {
			lastErr = err
		}
	}
	return "", fmt.Errorf("failed to extract embedded vtracer engine: %w", lastErr)
}

func writeEmbeddedBinary(bin []byte, path string) error {
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, bin, 0o755); err != nil {
		return err
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return err
	}
	return nil
}

// ConvertImageToSVG runs the vtracer binary over the raster image at inputPath
// and returns the generated vector SVG document.
func ConvertImageToSVG(inputPath string, opts SVGVectorOptions) ([]byte, error) {
	vtracer := ResolveVTracer()
	if vtracer == "" {
		return nil, fmt.Errorf("vtracer binary not found; set VTRACER_PATH or install vtracer")
	}

	tmpDir, err := os.MkdirTemp("", "fan-reubah-svg-*")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(tmpDir)

	outPath := filepath.Join(tmpDir, "out.svg")
	args := buildVTracerArgs(inputPath, outPath, opts)

	ctx, cancel := context.WithTimeout(context.Background(), SVGTimeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, vtracer, args...)
	if output, err := cmd.CombinedOutput(); err != nil {
		msg := strings.TrimSpace(string(output))
		if ctx.Err() == context.DeadlineExceeded {
			return nil, fmt.Errorf("vtracer timed out")
		}
		if msg == "" {
			return nil, fmt.Errorf("vtracer failed: %v", err)
		}
		return nil, fmt.Errorf("vtracer failed: %v: %s", err, msg)
	}

	svg, err := os.ReadFile(outPath)
	if err != nil {
		return nil, err
	}
	return svg, nil
}

// buildVTracerArgs assembles the CLI argument list, skipping empty options so
// that `--preset` selection keeps its tuned defaults.
func buildVTracerArgs(inputPath, outPath string, opts SVGVectorOptions) []string {
	args := []string{inputPath, outPath}
	push := func(flag, value string) {
		if value != "" {
			args = append(args, flag, value)
		}
	}

	push("--preset", opts.Preset)

	// Default to the seam-free mosaic (cutout) unless explicitly set to stacked.
	hier := opts.Hierarchical
	if hier == "" {
		hier = "cutout"
	}
	args = append(args, "--hierarchical", hier)

	push("--mode", opts.Mode)
	push("--filter-speckle", opts.FilterSpeckle)
	push("--color-precision", opts.ColorPrecision)
	push("--gradient-step", opts.GradientStep)
	push("--simplify", opts.Simplify)
	push("--max-colors", opts.MaxColors)
	push("--optimize", opts.Optimize)
	push("--path-precision", opts.PathPrecision)
	push("--threshold", opts.Threshold)
	push("--watershed-detail", opts.WatershedDetail)
	if opts.Adaptive {
		args = append(args, "--adaptive")
	}

	return args
}
