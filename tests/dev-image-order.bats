#!/usr/bin/env bats
# tests/dev-image-order.bats
# The tool image installs its largest layer first: each tool's COPY + RUN pair in containers/dev/Containerfile
# carries its measured layer size (`# layer: N MB`), and the sizes never increase down the file.

@test "dev Containerfile: every tool records its layer size, largest first" {
  local -r cf="${BATS_TEST_DIRNAME}/../containers/dev/Containerfile"
  run awk '
    /^# layer: [0-9.]+ MB$/ { size = $3; next }
    /^COPY scripts\/ci\/setup-[a-z0-9-]+\.sh / {
      if (size == "") { print "no layer size above: " $0; bad = 1 }
      else if (last != "" && size + 0 > last + 0) { print "larger than the one before: " $0; bad = 1 }
      if (size != "") last = size
      size = ""; n++
    }
    END { if (n == 0) { print "no tool layers"; bad = 1 } exit bad }
  ' "${cf}"
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
}
