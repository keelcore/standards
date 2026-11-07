package main

import (
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"

	standards "github.com/keelcore/standards"
)

// within reports whether dest is target itself or a path below it.
func within(target, dest string) bool {
	rel, err := filepath.Rel(target, dest)
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

func TestDestination(t *testing.T) {
	cases := []struct {
		path string
		want string
		ok   bool
	}{
		{"governance", "out/governance", true},
		{"governance/coding.md", "out/governance/coding.md", true},
		{"governance/ai/conduct.md", "out/governance/ai/conduct.md", true},
		{"../escape.md", "", false},
		{"governance/../../escape.md", "", false},
	}
	for _, c := range cases {
		got, err := destination("out", c.path)
		if (err == nil) != c.ok {
			t.Errorf("destination(out, %q): err = %v, want ok=%v", c.path, err, c.ok)
			continue
		}
		if c.ok && got != filepath.FromSlash(c.want) {
			t.Errorf("destination(out, %q) = %q, want %q", c.path, got, c.want)
		}
	}
}

// FuzzDestination: whatever the embedded path, a destination that is returned lies under the target.
func FuzzDestination(f *testing.F) {
	for _, seed := range []string{"governance", "governance/coding.md", "../x", "a/../../b", "/abs", ".", ""} {
		f.Add("out", seed)
	}
	f.Fuzz(func(t *testing.T, target, path string) {
		if target == "" {
			t.Skip()
		}
		dest, err := destination(target, path)
		if err != nil {
			return
		}
		if !within(filepath.Clean(target), dest) {
			t.Fatalf("destination(%q, %q) = %q: outside the target", target, path, dest)
		}
	})
}

// TestMaterialize: every embedded governance file lands under the target with its content.
func TestMaterialize(t *testing.T) {
	target := t.TempDir()
	if err := materialize(target); err != nil {
		t.Fatal(err)
	}
	n := 0
	err := fs.WalkDir(standards.Governance, "governance", func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		want, _ := standards.Governance.ReadFile(path)
		got, rerr := os.ReadFile(filepath.Join(target, path))
		if rerr != nil || string(got) != string(want) {
			t.Errorf("%s: not materialized as embedded (%v)", path, rerr)
		}
		n++
		return nil
	})
	if err != nil || n == 0 {
		t.Fatalf("walk: %v, %d files", err, n)
	}
}
