package main

import (
	"context"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gorilla/mux"
	"github.com/meimolihan/fan-reubah/internal/assets"
	"github.com/meimolihan/fan-reubah/internal/handlers"
)

// buildVersion 由发布构建通过 -ldflags -X main.buildVersion=... 注入；本地未注入时使用默认值。
var buildVersion = "1.0.5"

func main() {
	// 子命令：fan-reubah status | uninstall | -version
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "status":
			os.Exit(rbStatus())
		case "uninstall":
			os.Exit(rbUninstall(os.Args[2:]))
		case "-version", "--version", "-v":
			fmt.Printf("fan-reubah %s\n", buildVersion)
			os.Exit(0)
		}
	}

	// Initialize logger
	logger := log.New(os.Stdout, "[FAN-REUBAH] ", log.LstdFlags|log.Lshortfile)

	// Create router and setup routes
	r := setupRouter()

	// Create server with timeouts and other configurations
	srv := &http.Server{
		Handler:           r,
		Addr:              getPort(),
		WriteTimeout:      120 * time.Second,
		ReadTimeout:       120 * time.Second,
		ReadHeaderTimeout: 15 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    1 << 20, // 1MB
	}

	// Channel to listen for errors coming from the listener.
	serverErrors := make(chan error, 1)

	// Start the server
	go func() {
		logger.Printf("Listening on [::]%s", srv.Addr)
		serverErrors <- srv.ListenAndServe()
	}()

	// Channel to listen for an interrupt or terminate signal from the OS.
	shutdown := make(chan os.Signal, 1)
	signal.Notify(shutdown, os.Interrupt, syscall.SIGTERM)

	// Blocking main and waiting for shutdown.
	select {
	case err := <-serverErrors:
		logger.Fatalf("Error starting server: %v", err)

	case sig := <-shutdown:
		logger.Printf("Start shutdown... \nSignal: %v", sig)

		// Give outstanding requests a deadline for completion.
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()

		// Asking listener to shut down and shed load.
		if err := srv.Shutdown(ctx); err != nil {
			logger.Printf("Graceful shutdown did not complete in %v : %v", 15*time.Second, err)
			if err := srv.Close(); err != nil {
				logger.Fatalf("Could not stop server gracefully : %v", err)
			}
		}
	}
}

func setupRouter() *mux.Router {
	r := mux.NewRouter()

	// Middleware for all routes
	r.Use(loggingMiddleware)
	r.Use(securityHeadersMiddleware)
	r.Use(recoveryMiddleware)

	// Serve static files with caching (embedded in the binary; falls back to
	// the on-disk "static" dir when running from a source checkout).
	r.PathPrefix("/static/").Handler(
		http.StripPrefix("/static/", staticServer()),
	)

	// Routes
	r.HandleFunc("/", handlers.ShowUploadForm).Methods("GET")
	r.HandleFunc("/process", handlers.ProcessImage).Methods("POST")
	r.HandleFunc("/process/svg", handlers.ConvertToSVG).Methods("POST")
	r.HandleFunc("/process/merge-pdf", handlers.MergePDF).Methods("POST")
	r.HandleFunc("/process/document", handlers.ConvertDocument).Methods("POST")

	return r
}

// Middleware functions
func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf(
			"%s %s %s",
			r.Method,
			r.RequestURI,
			time.Since(start),
		)
	})
}

func securityHeadersMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-XSS-Protection", "1; mode=block")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
		next.ServeHTTP(w, r)
	})
}

func recoveryMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if err := recover(); err != nil {
				log.Printf("panic: %+v", err)
				http.Error(w, "Internal Server Error", http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// func cacheMiddleware(next http.Handler) http.Handler {
// 	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
// 		w.Header().Set("Cache-Control", "public, max-age=31536000")
// 		next.ServeHTTP(w, r)
// 	})
// }

func getPort() string {
	if port := os.Getenv("PORT"); port != "" {
		return ":" + port
	}
	return ":8081"
}

// staticServer serves the bundled frontend static files, or the on-disk
// "static" directory when the binary has no embedded assets.
func staticServer() http.Handler {
	if sub, err := fs.Sub(assets.Web(), "web/static"); err == nil {
		if _, err := fs.Stat(sub, "css/styles.css"); err == nil {
			return http.FileServer(http.FS(sub))
		}
	}
	return http.FileServer(http.Dir("static"))
}
