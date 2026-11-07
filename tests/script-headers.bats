#!/usr/bin/env bats
# tests/script-headers.bats
# Line 2 of every canonical script and shared library names the file: its path, or its file name.

@test "every canonical script and library names itself on line 2" {
  cd "${BATS_TEST_DIRNAME}/.."
  local f bad=''
  while IFS= read -r f; do
    case "$(sed -n 2p "${f}")" in
      "# ${f}" | "# $(basename "${f}")" | "# ${f} "* | "# $(basename "${f}") "*) ;;
      *) bad+="${f}: $(sed -n 2p "${f}")"$'\n' ;;
    esac
  done < <(git ls-files 'scripts/*.sh' 'scripts/**/*.sh' | grep -v '\.local\.sh$' | sort -u)
  [ -z "${bad}" ] || { printf '%s' "${bad}"; return 1; }
}
