package storage

import (
	"io"
	"time"
)

// Meta holds metadata about a stored backup.
type Meta struct {
	LastModified *time.Time `json:"last_modified"`
	Exists       bool       `json:"exists"`
}

// Storage defines the interface for backup persistence.
// Swap the implementation to move from local disk to S3/R2.
type Storage interface {
	GetMeta(backupId string) (Meta, error)
	Save(backupId string, data []byte, clientTimestamp time.Time) error
	Get(backupId string) (io.ReadCloser, *time.Time, error)
}
