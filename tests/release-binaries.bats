#!/usr/bin/env bats
# tests/release-binaries.bats
# Checksums, dist permissions and OpenVEX for a repository that ships binaries. Which files are
# release binaries, and the document's name, come from config.

setup() {
  load helpers-consumer
  consumer_setup
  mkdir dist
  printf 'b\n' > dist/app-linux-amd64
  printf 'n\n' > dist/notes.json
  printf 's\n' > dist/app-linux-amd64.bundle
}

@test "checksums.sh: everything in dist by default, without signatures" {
  run bash scripts/release/checksums.sh
  [ "${status}" -eq 0 ]
  grep -q 'dist/app-linux-amd64$' dist/SHA256SUMS
  grep -q 'dist/notes.json$' dist/SHA256SUMS
  ! grep -q 'bundle' dist/SHA256SUMS
}

@test "checksums.sh: config narrows it to the binaries" {
  mkdir config
  printf 'app-*\n' > config/release-binaries.local.txt
  run bash scripts/release/checksums.sh
  [ "${status}" -eq 0 ]
  grep -q 'dist/app-linux-amd64$' dist/SHA256SUMS
  ! grep -q 'notes.json' dist/SHA256SUMS
}

@test "checksums.sh --verify: catches a changed file" {
  bash scripts/release/checksums.sh > /dev/null
  run bash scripts/release/checksums.sh --verify
  [ "${status}" -eq 0 ]
  printf 'x\n' >> dist/app-linux-amd64
  run bash scripts/release/checksums.sh --verify
  [ "${status}" -ne 0 ]
}

@test "dist-chmod.sh: makes the configured binaries executable, and only those" {
  mkdir config
  printf 'app-*\n' > config/release-binaries.local.txt
  run bash scripts/build/dist-chmod.sh
  [ "${status}" -eq 0 ]
  [ -x dist/app-linux-amd64 ]
  [ ! -x dist/notes.json ]
}

@test "vex.sh: names the document after the project" {
  printf 'module github.com/acme/widget\n' > go.mod
  stub govulncheck 'printf "{\"statements\":[]}"'
  run bash scripts/release/vex.sh --out-dir dist
  [ "${status}" -eq 0 ]
  [ -f dist/widget.openvex.json ]
}

@test "lint vex.sh: the checks reject an invalid document, and accept a valid one" {
  printf 'module github.com/acme/widget\n' > go.mod
  printf '{"@context":"wrong"}' > dist/widget.openvex.json
  run bash scripts/lint/vex.sh
  [ "${status}" -ne 0 ]
  printf '{"@context":"https://openvex.dev/ns/v0.2.0","timestamp":"2026-01-01T00:00:00Z","statements":[{"vulnerability":{"name":"V"},"products":[{"@id":"p"}],"status":"fixed"}]}' > dist/widget.openvex.json
  run bash scripts/lint/vex.sh
  [ "${status}" -eq 0 ]
}
