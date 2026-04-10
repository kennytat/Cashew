package handlers

import (
	"cashew-sync/middleware"
	"cashew-sync/storage"
	"io"
	"net/http"
	"time"
)

func UploadHandler(store storage.Storage) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		backupId, ok := middleware.ValidateBackupId(r)
		if !ok {
			http.Error(w, `{"error":"invalid backup id"}`, http.StatusBadRequest)
			return
		}

		// Parse client timestamp from header.
		tsHeader := r.Header.Get("X-Timestamp")
		if tsHeader == "" {
			http.Error(w, `{"error":"missing X-Timestamp header"}`, http.StatusBadRequest)
			return
		}
		clientTime, err := time.Parse(time.RFC3339, tsHeader)
		if err != nil {
			http.Error(w, `{"error":"invalid X-Timestamp format, use RFC3339"}`, http.StatusBadRequest)
			return
		}

		// Check if server already has a newer copy.
		meta, err := store.GetMeta(backupId)
		if err != nil {
			http.Error(w, `{"error":"internal"}`, http.StatusInternalServerError)
			return
		}
		if meta.Exists && meta.LastModified != nil && !clientTime.After(*meta.LastModified) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusConflict)
			w.Write([]byte(`{"error":"server_copy_is_newer","server_last_modified":"` + meta.LastModified.Format(time.RFC3339) + `"}`))
			return
		}

		// Read the body.
		data, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, `{"error":"failed to read body"}`, http.StatusBadRequest)
			return
		}
		if len(data) == 0 {
			http.Error(w, `{"error":"empty body"}`, http.StatusBadRequest)
			return
		}

		// Save.
		if err := store.Save(backupId, data, clientTime); err != nil {
			http.Error(w, `{"error":"internal"}`, http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ok"}`))
	}
}
