# Bash Script Standards

These rules govern all bash scripts in this project. They are non-negotiable.

**Maturity:** Required
**Version:** 1.2.0
**Last Reviewed:** 2026-03-17

Each rule has a stable canonical ID (`R1`–`R42`) used when these rules are
cited elsewhere. Numbers do not renumber across edits.

## Portability and Shell Baseline

- **R1.** Google Bash style unless overridden by rules below.
- **R2.** Darwin-compatible; Bash 3.x compatible — no `mapfile`, no `declare -A`.
- **R3.** Shebang: `#!/usr/bin/env bash` always.
- **R4.** Use the explicit shell options block (not `set -euo pipefail` shorthand).

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

- **R5.** `main` is the FIRST function defined in the file.
- **R6.** `main "${@:-}"` is the LAST line of the file.
- **R7.** Always provide the complete script, never a patch or diff.
- **R8.** Never omit any referenced function.

## Functions

- **R9.** All function declarations preceded by keyword `function`.
- **R10.** No `function_` prefix on function names.
- **R11.** Function names: lowercase, simple, reflect intent.
- **R12.** One statement per line.
- **R13.** No function body > 10 lines unless reduction is genuinely impossible.
- **R14.** Prefer decomposition into small, reusable helpers.
- **R15.** Load-bearing functions: log intent first, then log result.

## Arguments and Validation

- **R16.** Validate argument count.
- **R17.** Validate required arguments are non-null.
- **R18.** Support empty argument lists under `set -u` using `"${@:-}"`.
- **R19.** `validate_args` must allow an empty first argument when zero arguments are valid:

  ```bash
  function validate_args() {
    if [ "${#}" -gt 0 ] && [ -z "${1:-}" ]; then
      log '❌ Error: Unexpected empty argument'
      exit 1
    fi
  }
  ```

## Variables

- **R20.** Always `"${var}"` style for variable expansion.
- **R21.** Quote expansions unless unquoted behavior is explicitly required.
- **R22.** `local -r` for immutable locals NOT assigned from subshell.
- **R23.** Mutable locals or subshell-assigned: declare on one line, assign on next:

  ```bash
  local result
  result="$(some_command)"
  ```

- **R24.** Single quotes for literal strings with no expansion needed.

## Logging and Output

- **R25.** Route all messaging through a `log` function.
- **R26.** `log` must tee to a well-known log file.
- **R27.** Capture original stdout in `main` with `exec 5>&1`; `log` writes to FD 5.
- **R28.** Use emoji for key accomplishments.
- **R29.** Load-bearing functions log both intent and result.

## Printing

- **R30.** Prefer `printf` over `echo`.
- **R31.** `printf` format string must be single-quoted with explicit format specifiers.
- **R32.** Use `echo` only with no parameters and no formatting concerns.

## Globals

- **R33.** Never use the keyword `global`.
- **R34.** All globals shall be declared after the header comment block and before `function main`.
- **R35.** All globals shall be immutable after initialization.
- **R36.** Immutability shall be enforced with `declare -r`; the one exception is a global whose
  initialization requires multi-statement evaluation — in that case declare on one line,
  assign on the next (the variable remains effectively immutable by convention):

  ```bash
  # simple: single-expression initialization
  declare -r DEPLOY_ENV="${DEPLOY_ENV:-staging}"

  # multi-statement: declare first, then assign
  declare LOG_FILE
  LOG_FILE="$(mktemp /tmp/script.XXXXXX)"
  ```

- **R37.** Environment variables shall be declared as globals with `declare -rx`, using the
  default-value idiom. This applies to both imported and exported environment variables:

  ```bash
  declare -rx SOME_VAR="${SOME_VAR:-default_value}"
  ```

- **R38.** Global names SHALL be uppercase.
- **R39.** Never declare a global inside a function scope.

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

## Embedded Code (Heredocs)

- **R40.** Never embed code blocks (PHP, TOML, ini, shell, conf, etc.) as heredocs inside a bash
  script. Code in heredocs cannot be linted by its native tooling, is invisible to static
  analysis, and causes bash quoting edge cases that are impossible to debug.

- **R41.** Extract every embedded code block to a **sibling file** in the same directory as the
  script, with the correct source extension for linting (`.php`, `.toml`, `.sh`, `.conf`,
  etc.). Load it at runtime with `cat`:

  ```bash
  php_script=$(cat "${SCRIPT_DIR}/myscript-step.php")
  ```

- **R42.** Templates that require runtime variable substitution use `@PLACEHOLDER@` notation and
  `sed` for substitution. Never use an unquoted heredoc (`<< EOF`) for variable injection:

  ```bash
  php_script=$(sed \
    -e "s|@MY_VAR@|${MY_VAR}|g" \
    "${SCRIPT_DIR}/myscript-template.php")
  ```
