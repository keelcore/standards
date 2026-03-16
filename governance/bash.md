# Bash Script Standards

These rules govern all bash scripts in this project. They are non-negotiable.

**Maturity:** Required
**Version:** 1.1.0
**Last Reviewed:** 2026-03-16

## Portability and Shell Baseline

1. Google Bash style unless overridden by rules below.
2. Darwin-compatible; Bash 3.x compatible — no `mapfile`, no `declare -A`.
3. Shebang: `#!/usr/bin/env bash` always.
4. Use the explicit shell options block (not `set -euo pipefail` shorthand).

## Required Shell Options Block

Every script begins with:

```bash
#!/usr/bin/env bash
# <script name>
# <functional description, with arguments if needed>

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail
```

## Script Structure

5. `main` is the FIRST function defined in the file.
6. `main "${@:-}"` is the LAST line of the file.
7. Always provide the complete script, never a patch or diff.
8. Never omit any referenced function.

## Functions

9. All function declarations preceded by keyword `function`.
10. No `function_` prefix on function names.
11. Function names: lowercase, simple, reflect intent.
12. One statement per line.
13. No function body > 10 lines unless reduction is genuinely impossible.
14. Prefer decomposition into small, reusable helpers.
15. Load-bearing functions: log intent first, then log result.

## Arguments and Validation

16. Validate argument count.
17. Validate required arguments are non-null.
18. Support empty argument lists under `set -u` using `"${@:-}"`.
19. `validate_args` must allow an empty first argument when zero arguments are valid:

```bash
function validate_args() {
  if [ "${#}" -gt 0 ] && [ -z "${1:-}" ]; then
    log '❌ Error: Unexpected empty argument'
    exit 1
  fi
}
```

## Variables

20. Always `"${var}"` style for variable expansion.
21. Quote expansions unless unquoted behavior is explicitly required.
22. `local -r` for immutable locals NOT assigned from subshell.
23. Mutable locals or subshell-assigned: declare on one line, assign on next:

```bash
local result
result="$(some_command)"
```

24. Single quotes for literal strings with no expansion needed.

## Logging and Output

25. Route all messaging through a `log` function.
26. `log` must tee to a well-known log file.
27. Capture original stdout in `main` with `exec 5>&1`; `log` writes to FD 5.
28. Use emoji for key accomplishments.
29. Load-bearing functions log both intent and result.

## Printing

30. Prefer `printf` over `echo`.
31. `printf` format string must be single-quoted with explicit format specifiers.
32. Use `echo` only with no parameters and no formatting concerns.

## Globals

33. Never use the keyword `global`.
34. All globals shall be declared after the header comment block and before `function main`.
35. All globals shall be immutable after initialization.
36. Immutability shall be enforced with `declare -r`; the one exception is a global whose
    initialization requires multi-statement evaluation — in that case declare on one line,
    assign on the next (the variable remains effectively immutable by convention):

```bash
# simple: single-expression initialization
declare -r DEPLOY_ENV="${DEPLOY_ENV:-staging}"

# multi-statement: declare first, then assign
declare LOG_FILE
LOG_FILE="$(mktemp /tmp/script.XXXXXX)"
```

37. Environment variables shall be declared as globals with `declare -rx`, using the default-value
    idiom. This applies to both imported and exported environment variables:

```bash
declare -rx SOME_VAR="${SOME_VAR:-default_value}"
```

38. Global names SHALL be uppercase.
39. Never declare a global inside a function scope.

## Standard `log` Function Pattern

```bash
function log() {
  local msg
  msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/SCRIPTNAME.log' >&5
}
```

## Standard `main` Pattern

```bash
function main() {
  exec 5>&1
  validate_args "${@:-}"
  # ... work ...
}
# ... helper functions ...
main "${@:-}"
```

## GitHub Actions `validate_args` Quirk

In GitHub Actions, `shell: bash` expands an empty `$@` to a single empty-string argument when
using `"${@:-}"`. Unadjusted, this triggers the argument check spuriously. Apply the following
fixups based on script type:

**Zero-argument scripts** — tolerate the single-empty-string artifact; reject any real arg:

```bash
function validate_args() {
  if [ "${#}" -gt 1 ] || [ -n "${1:-}" ]; then
    log '❌ Error: Unexpected argument'
    exit 1
  fi
}
```

**Argument-taking scripts** — tolerate the artifact; still catch multiple or non-empty extra args:

```bash
function validate_args() {
  if [ "${#}" -gt 1 ] && [ -n "${1:-}" ]; then
    log '❌ Error: Too many arguments'
    exit 1
  fi
}
```

Do NOT change the call site from `"${@:-}"` to `"$@"` — fix the body only.
