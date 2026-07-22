# Agent Rules

## PowerShell CLI Command Safety
- **Never inline Markdown backticks in PowerShell double quotes**: PowerShell interprets `` `b `` as an ASCII Backspace control character (`0x08`).
- **Use body files for GitHub PR descriptions**: Always write multi-line PR descriptions to a file and pass `--body-file` or `gh api -F body=@file.md` to prevent terminal string escaping artifacts.
