package handlers

import (
	"cashew-sync/middleware"
	"cashew-sync/storage"
	"encoding/json"
	"net/http"
)

func MetaHandler(store storage.Storage) http.HandlerFunc {
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

		meta, err := store.GetMeta(backupId)
		if err != nil {
			http.Error(w, `{"error":"internal"}`, http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(meta)
	}
}
