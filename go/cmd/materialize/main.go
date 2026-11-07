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

func materialize(target string) error {
	return fs.WalkDir(standards.Governance, "governance", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		dest, err := destination(target, path)
		if err != nil {
			return err
		}
		if d.IsDir() {
			return os.MkdirAll(dest, 0o755)
		}
		data, err := standards.Governance.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(dest, data, 0o644)
	})
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
