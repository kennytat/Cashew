package handlers

import (
	"cashew-sync/middleware"
	"cashew-sync/storage"
	"io"
	"net/http"
	"time"
)

func DownloadHandler(store storage.Storage) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		backupId, ok := middleware.ValidateBackupId(r)
		if !ok {
			http.Error(w, `{"error":"invalid backup id"}`, http.StatusBadRequest)
			return
		}

		reader, lastModified, err := store.Get(backupId)
		if err != nil {
			http.Error(w, `{"error":"internal"}`, http.StatusInternalServerError)
			return
		}
		if reader == nil {
			http.Error(w, `{"error":"not found"}`, http.StatusNotFound)
			return
		}
		defer reader.Close()

		w.Header().Set("Content-Type", "application/octet-stream")
		if lastModified != nil {
			w.Header().Set("X-Last-Modified", lastModified.Format(time.RFC3339))
		}
		w.WriteHeader(http.StatusOK)
		io.Copy(w, reader)
	}
}
