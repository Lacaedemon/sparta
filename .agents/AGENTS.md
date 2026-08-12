# Agent Rules

## PowerShell CLI Command Safety
- **Never inline Markdown backticks in PowerShell double quotes**: PowerShell interprets `` `b `` as an ASCII Backspace control character (`0x08`).
- **Use body files for GitHub PR descriptions**: Always write multi-line PR descriptions to a file and pass `--body-file` or `gh api -F body=@file.md` to prevent terminal string escaping artifacts.

## Godot 4.7 Testing & CLI Environment
- **Missing Godot 4.7 CLI**: If the Godot 4.7 CLI is missing from the environment, it can be installed headlessly via:
  ```bash
  wget -q https://github.com/godotengine/godot/releases/download/4.7-stable/Godot_v4.7-stable_linux.x86_64.zip -O /tmp/godot.zip && mkdir -p ~/.local/bin/ && unzip -q /tmp/godot.zip -d ~/.local/bin/ && mv ~/.local/bin/Godot_v4.7-stable_linux.x86_64 ~/.local/bin/godot && chmod +x ~/.local/bin/godot && export PATH="~/.local/bin:$PATH"
  ```
- **Local Validation**: Run local tests and validation using `./tools/check.sh test` or `./tools/check.sh validate`.

## GDScript Performance Best Practices
- **Distance Checks**: Prefer using `distance_squared_to()` over `distance_to()` when comparing against distance thresholds, as it bypasses the expensive square root operation.
