// materialize extracts embedded governance files to a target directory.
//
// Usage:
//
//	go run github.com/keelcore/standards/go/cmd/materialize <target-dir>
//
// Typical go:generate invocation:
//
//	//go:generate go run github.com/keelcore/standards/go/cmd/materialize .standards
package main

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	standards "github.com/keelcore/standards"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: materialize <target-dir>")
		os.Exit(1)
	}
	target := os.Args[1]
	if err := materialize(target); err != nil {
		fmt.Fprintf(os.Stderr, "materialize: %v\n", err)
		os.Exit(1)
	}
}

// materialize writes every embedded governance file under target. The walk only lists the entries; the
// directories and files are written after it, outside the walk's callback.
func materialize(target string) error {
	type entry struct {
		path string
		dir  bool
	}
	var entries []entry
	err := fs.WalkDir(standards.Governance, "governance", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		entries = append(entries, entry{path: path, dir: d.IsDir()})
		return nil
	})
	if err != nil {
		return err
	}
	for _, e := range entries {
		dest, err := destination(target, e.path)
		if err != nil {
			return err
		}
		if e.dir {
			err = os.MkdirAll(dest, 0o750)
		} else {
			err = writeEmbedded(e.path, dest)
		}
		if err != nil {
			return err
		}
	}
	return nil
}

// writeEmbedded copies the embedded file at path to dest, readable by its owner only.
func writeEmbedded(path, dest string) error {
	data, err := standards.Governance.ReadFile(path)
	if err != nil {
		return err
	}
	return os.WriteFile(dest, data, 0o600)
}

// destination is where an embedded path is written under target; a path that would land outside
// target is refused.
func destination(target, path string) (string, error) {
	root := filepath.Clean(target)
	dest := filepath.Join(root, filepath.FromSlash(path))
	rel, err := filepath.Rel(root, dest)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("%q is outside %q", path, target)
	}
	return dest, nil
}
