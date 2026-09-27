## Shell tooling on Windows: three tools drop `\r`, native node needs Windows paths, and `check.sh`'s `info` writes to stdout

Measured 2026-09-26 while writing `tools/lib/tests/test-upsert-pr-body-section.sh` and the `markdown` check in `tools/check.sh`, in Git Bash on Windows.

### Three tools silently drop `\r`, so a CRLF regression test can pass against the bug

Git Bash's gawk reads input in text mode and drops the `\r` before each `\n`: `printf 'x\r\n' | awk '{print length($0)}'` prints 1, and with `-v BINMODE=1` it prints 2.

A native Windows jq drops `\r` from `\r\n` on input and writes `\n` as `\r\n` on output, unless it is given `--binary`.

Git Bash's bash drops `\r` from command-substitution output, so a `\r`-bearing string passed through `$(...)` arrives without it.

Together they made a CRLF regression test pass against the unfixed script, because the script's own awk never saw the `\r` it was meant to mishandle.
Only a mutation run exposed that: remove the fix, and the test still passed.

- **Do:** put wrapper `awk` (`-v BINMODE=1`) and `jq` (`--binary`, when the build accepts it) scripts on `PATH` inside a test that feeds CRLF input.

- **Do:** check `\r` bytes with an awk regex over the file itself, not with a string built by the shell.

- **Do:** remove the fix and confirm the test fails before trusting a green CRLF test on Windows.

- **Don't:** trust `grep -c $'\r$'` here; it counted every line of a file with one CR in it.

- **Don't:** assume the Linux CI run will prove the test bites.
  WSL Ubuntu on this machine has no jq, so the test skips there.

### A native Windows node cannot open a Git Bash `/c/...` path

`node /c/Users/.../script.mjs` fails with `MODULE_NOT_FOUND`.
Convert the path first with `cygpath -m` when `cygpath` exists.
It is absent on Linux and macOS, so the conversion is a no-op there.

### `info` and `warn` in `tools/check.sh` write to stdout

A helper whose stdout the caller captures (`dir="$(fetch_something)"`) must send its progress and warnings to stderr (`info "..." >&2`).
Otherwise the message is glued onto the captured value.
The first version of the `markdown` check's fetch helper did this, and node then tried to open a path that began with the warning text.
`err` already writes to stderr.
