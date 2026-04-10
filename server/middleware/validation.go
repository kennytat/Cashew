package middleware

import (
	"net/http"
	"regexp"
)

var validBackupId = regexp.MustCompile(`^[a-f0-9]{64}$`)

// ValidateBackupId extracts and validates the backupId from the URL path.
// Expected path format: /prefix/{backupId}
func ValidateBackupId(r *http.Request) (string, bool) {
	// Last path segment is the backupId.
	path := r.URL.Path
	id := path[len(path)-64:]
	if len(path) < 65 || !validBackupId.MatchString(id) {
		return "", false
	}
	return id, true
}

// MaxBodySize wraps a handler with a request body size limit.
func MaxBodySize(next http.HandlerFunc, maxBytes int64) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
		next(w, r)
	}
}
