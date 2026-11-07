package main

import (
	"path/filepath"
	"strings"
	"testing"
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
