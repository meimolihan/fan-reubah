package handlers

import (
	"html/template"
	"io/fs"
	"net/http"
	"sync"

	"github.com/meimolihan/fan-reubah/internal/assets"
)

// templates prefers the frontend bundled inside the binary (go:embed) and
// falls back to the on-disk sources when running from a source checkout
// without prepared assets.
//
// 采用惰性初始化：包 init 不再解析模板，确保 `fan-reubah --version` 等
// 无需渲染页面的子命令即使在内嵌资源缺失、当前目录无 templates/ 时也不会 panic。
var (
	templates     *template.Template
	templatesOnce sync.Once
)

func getTemplates() *template.Template {
	templatesOnce.Do(func() {
		templates = parseTemplates()
	})
	return templates
}

func parseTemplates() *template.Template {
	if sub, err := fs.Sub(assets.Web(), "web/templates"); err == nil {
		if _, err := fs.Stat(sub, "index.html"); err == nil {
			return template.Must(template.ParseFS(sub,
				"*.html",
				"components/*.html",
				"pages/*.html",
			))
		}
	}
	return template.Must(template.ParseFiles(
		"templates/index.html",
		"templates/components/nav.html",
		"templates/components/tabs.html",
		"templates/components/upload.html",
		"templates/components/quick-actions.html",
		"templates/components/options-panel.html",
		"templates/components/progress-result.html",
		"templates/components/batch-upload.html",
		"templates/components/document-conversion.html",
		"templates/components/svg-conversion.html",
		"templates/pages/image.html",
		"templates/pages/document.html",
		"templates/pages/batch.html",
		"templates/pages/svg.html",
	))
}

func ShowUploadForm(w http.ResponseWriter, r *http.Request) {
	if err := getTemplates().ExecuteTemplate(w, "index.html", nil); err != nil {
		http.Error(w, "Failed to render template", http.StatusInternalServerError)
	}
}
