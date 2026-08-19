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

## Cursor Cloud specific instructions
This repo is a single product: a **Godot 4.7 Standard** (GDScript) game with two
modes launched from `scenes/MainMenu.tscn` -- the real-time tactical **Battle**
(`scenes/Battle.tscn`) and the turn-based **Campaign** (`scenes/Campaign.tscn`).
There is no backend/server/database -- everything runs inside the Godot engine.

- **Godot binary:** the startup update script installs Godot 4.7 to
  `/usr/local/bin/godot` (already on `PATH`). `gdlint`/`gdformat` (gdtoolkit) are
  installed to `~/.local/bin`, which is added to `PATH` via `~/.bashrc` -- so a
  fresh non-login shell may need `export PATH="$HOME/.local/bin:$PATH"` before
  `gdlint` resolves (only the optional `lint` check needs it).
- **Lint / test / validate / build-run:** use `tools/check.sh` (see
  `tools/README.md` and `test/README.md`); it vendors GUT into `addons/gut/`
  on demand and runs `godot --headless --import` itself, so no separate
  bootstrap is needed. `tools/check.sh` (default) runs validate + the GUT suite
  + doc checks. The **full GUT suite takes ~7 minutes** (2769 tests) -- budget a
  generous timeout; it is not hung. For a `scripts/` change also run
  `patch_coverage` in the *same* invocation (see `CLAUDE.md`).
- **Running/seeing the game (no display):** the VM is headless, so you cannot open
  the editor. Drive a real battle through the demo pipeline instead (see the
  `sparta-demos` skill and `demos/README.md`). `xvfb-run`, `ffmpeg`, and `jq` are
  available. Record a clip with Movie Maker under Xvfb -- e.g.
  `SPARTA_DEMO_INPUT="res://demos/inputs/<name>.json" xvfb-run -a godot --rendering-driver opengl3 --path . --write-movie /tmp/out.avi --fixed-fps 30 --quit-after 260 res://tools/demo/DemoInputRecorder.tscn`
  then convert with `ffmpeg`. **Do not** pass `--headless` to a Movie Maker /
  frame-capture run -- it crashes with a null-texture error (dummy renderer); use
  `xvfb-run` + `--rendering-driver opengl3` (see `CLAUDE.md`). Machine-readable
  **state dumps** (`tools/demo/dump-state.sh`) do run under `--headless`.
