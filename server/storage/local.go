package storage

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

// metaFile is the JSON sidecar that records the client-provided timestamp.
type metaFile struct {
	LastModified time.Time `json:"last_modified"`
}

// Local implements Storage using the local filesystem.
type Local struct {
	Dir string // e.g. "./backups"
}

func NewLocal(dir string) (*Local, error) {
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("create storage dir: %w", err)
	}
	return &Local{Dir: dir}, nil
}

func (l *Local) dataPath(backupId string) string {
	return filepath.Join(l.Dir, backupId+".enc")
}

func (l *Local) metaPath(backupId string) string {
	return filepath.Join(l.Dir, backupId+".meta.json")
}

func (l *Local) GetMeta(backupId string) (Meta, error) {
	raw, err := os.ReadFile(l.metaPath(backupId))
	if os.IsNotExist(err) {
		return Meta{Exists: false}, nil
	}
	if err != nil {
		return Meta{}, fmt.Errorf("read meta: %w", err)
	}

	var mf metaFile
	if err := json.Unmarshal(raw, &mf); err != nil {
		return Meta{}, fmt.Errorf("parse meta: %w", err)
	}
	t := mf.LastModified.UTC()
	return Meta{LastModified: &t, Exists: true}, nil
}

func (l *Local) Save(backupId string, data []byte, clientTimestamp time.Time) error {
	// Atomic write: write to temp file, then rename.
	tmpData := l.dataPath(backupId) + ".tmp"
	if err := os.WriteFile(tmpData, data, 0644); err != nil {
		return fmt.Errorf("write data tmp: %w", err)
	}

	mf := metaFile{LastModified: clientTimestamp.UTC()}
	raw, err := json.Marshal(mf)
	if err != nil {
		os.Remove(tmpData)
		return fmt.Errorf("marshal meta: %w", err)
	}

	tmpMeta := l.metaPath(backupId) + ".tmp"
	if err := os.WriteFile(tmpMeta, raw, 0644); err != nil {
		os.Remove(tmpData)
		return fmt.Errorf("write meta tmp: %w", err)
	}

	// Rename both atomically (as atomic as the OS allows).
	if err := os.Rename(tmpData, l.dataPath(backupId)); err != nil {
		os.Remove(tmpData)
		os.Remove(tmpMeta)
		return fmt.Errorf("rename data: %w", err)
	}
	if err := os.Rename(tmpMeta, l.metaPath(backupId)); err != nil {
		return fmt.Errorf("rename meta: %w", err)
	}
	return nil
}

func (l *Local) Get(backupId string) (io.ReadCloser, *time.Time, error) {
	meta, err := l.GetMeta(backupId)
	if err != nil {
		return nil, nil, err
	}
	if !meta.Exists {
		return nil, nil, nil // caller checks for nil to detect 404
	}

	f, err := os.Open(l.dataPath(backupId))
	if os.IsNotExist(err) {
		return nil, nil, nil
	}
	if err != nil {
		return nil, nil, fmt.Errorf("open data: %w", err)
	}
	return f, meta.LastModified, nil
}
