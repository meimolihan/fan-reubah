package handlers

import (
	"html/template"
	"io/fs"
	"net/http"

	"github.com/meimolihan/fan-reubah/internal/assets"
)

// templates prefers the frontend bundled inside the binary (go:embed) and
// falls back to the on-disk sources when running from a source checkout
// without prepared assets.
var templates = parseTemplates()

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
	if err := templates.ExecuteTemplate(w, "index.html", nil); err != nil {
		http.Error(w, "Failed to render template", http.StatusInternalServerError)
	}
}
