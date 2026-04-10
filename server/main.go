package main

import (
	"cashew-sync/handlers"
	"cashew-sync/middleware"
	"cashew-sync/storage"
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8085"
	}
	backupDir := os.Getenv("BACKUP_DIR")
	if backupDir == "" {
		backupDir = "./backups"
	}

	store, err := storage.NewLocal(backupDir)
	if err != nil {
		log.Fatalf("init storage: %v", err)
	}

	// 50 MB upload limit.
	const maxUploadBytes = 50 << 20

	mux := http.NewServeMux()
	mux.HandleFunc("/meta/", handlers.MetaHandler(store))
	mux.HandleFunc("/upload/", middleware.MaxBodySize(handlers.UploadHandler(store), maxUploadBytes))
	mux.HandleFunc("/download/", handlers.DownloadHandler(store))

	// Health check.
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"status":"ok"}`))
	})

	handler := corsMiddleware(mux)

	fmt.Printf("Cashew sync server listening on :%s (backups in %s)\n", port, backupDir)
	log.Fatal(http.ListenAndServe(":"+port, handler))
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, X-Timestamp")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
