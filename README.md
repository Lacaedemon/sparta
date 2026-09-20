# Sparta

[![codecov](https://codecov.io/gh/Lacaedemon/sparta/graph/badge.svg?token=NDG7G3MRTU)](https://codecov.io/gh/Lacaedemon/sparta)

A prototype that fuses grand strategy with real-time tactical battles. 
Built in **Godot 4.7** with GDScript.

Both layers are playable today:
a **real-time tactical battle** (the hardest and most differentiating piece, built first as a vertical slice)
and a **turn-based campaign map** with diplomacy.
They are already joined:
attacking a defended province on the campaign map launches the tactical battle and carries its result back.
See [`PLAN.md`](PLAN.md) for what has landed and what is next.

📖 **Documentation site:** <https://lacaedemon.github.io/sparta/> -- getting started,
controls, tactics, the replay system, architecture, and roadmap, with gameplay clips.
(Built with Quarto from `website/`; published via GitHub Pages.)

## Cloning

`gh-pages` (the rendered site and its per-PR previews) and `demo-media` (each
PR's recorded gameplay clip) hold generated output.
Nothing in the game, the tests, or the website sources needs either branch, and
together their current content is about 1.4 GB -- almost all of it `demo-media`,
which keeps one clip per PR forever.

The exclusion has to be configured **before the first fetch**.
`git clone` fetches every branch as part of cloning, so a `git config` line
added afterwards is too late to save anything:

```sh
git init sparta
cd sparta
git remote add origin https://github.com/Lacaedemon/sparta.git
git config --add remote.origin.fetch '^refs/heads/gh-pages'
git config --add remote.origin.fetch '^refs/heads/demo-media'
git fetch origin
git checkout main
```

If you have already cloned, those two `config` lines stop future fetches but do
not remove what is already present, and `git fetch --prune` does not remove it
either.
Drop the remote-tracking refs explicitly and let git collect the objects:

```sh
git config --add remote.origin.fetch '^refs/heads/gh-pages'
git config --add remote.origin.fetch '^refs/heads/demo-media'
git branch -rd origin/gh-pages origin/demo-media
git gc --prune=now
```

Both claims above were checked on git 2.55.0 against a scratch repository:
after `git clone` followed by `git config --add`, the excluded branch is still
present, and a subsequent `git fetch --prune` leaves it in place; configured
before the first fetch, it is never fetched at all.

`tools/check-worktree-state.sh` reports every worktree's branch, staleness, and
uncommitted work if you keep several checkouts around.
## Run it
1. Install **Godot 4.7.x -- Standard build** (not the .NET/C# build) from
   <https://godotengine.org/download/windows/>.
2. Open Godot, click **Import**, and select this folder's `project.godot`.
3. Press **F5** (Play). A title menu opens with two modes -- no art download required:
   - **Tactical Battle** -- the M1 real-time battle (units render as colored tokens).
   - **Campaign: Gallic War** -- the M2 turn-based province-conquest map (Rome vs the
     Gallic tribes). Click one of your (blue) armies, then an adjacent province to
     move or attack; **End Turn** runs the enemy; conquer every province to win.

## How to play

| Action | Control |
| --- | --- |
| Select a unit | Left-click |
| Select multiple | Left-click and drag a box |
| Move / attack | Right-click ground (move) or an enemy (attack) |
| Pan camera | `WASD` / arrow keys / screen edges |
| Zoom | Mouse wheel |

You command the **blue** army (top). Defeat the **red** army (bottom).

### Replays
Every battle is recorded automatically (`● REC`, top-center). When it ends, hit
**Watch Replay** to re-run it (`▶ REPLAY`), or **Load Replay** (top-right, also
on the end screen) to pick any earlier saved battle. Logs are tiny deterministic
seed-plus-orders files in `user://replays/` -- the same approach many strategy games use --
so they're handy for both re-watching battles and debugging. See
[REPLAY.md](REPLAY.md).

### Tactics that matter
- **Flanking:** hitting a unit from the side (x1.5) or rear (x2) deals far more damage
  and morale loss. Maneuver behind the enemy line.
- **Morale & routing:** units that lose enough soldiers or take flank hits will **rout**
  (flee, shown faded) and stop counting toward the battle. Routs spread to nearby allies.
- **Rock-paper-scissors:** **Cavalry** are fast and get a charge bonus, but **Spearmen**
  (with the spear marker) blunt that charge. Use cavalry to flank, spears to screen.
- **Disengaging:** right-click ground (a move order) to pull a unit *out* of melee --
  handy for retreating a battered regiment or redeploying cavalry to a new flank.
  It's risky: while marching away the unit shows its back, so the enemy it left gets
  free rear hits (x2) until it's clear. Stop the unit and it re-engages anything nearby.

## Project layout

```
project.godot          Godot project config (main scene = scenes/MainMenu.tscn)
scenes/MainMenu.tscn   Title screen: launch the battle (M1) or the campaign (M2)
scenes/Battle.tscn     Battle scene: camera + units container + selection + HUD
scenes/Campaign.tscn   Campaign map: province view/controller + campaign HUD
scripts/
  Battle.gd            Spawns armies, enemy AI, win/lose check, tick clock + replay orders
  Replay.gd            Deterministic record/playback (autoload): seeded RNG + order log
  Unit.gd              Regiment: stats, movement, melee, flanking, morale, routing
  SelectionManager.gd  Click + drag-box selection, move/attack orders
  CameraController.gd  WASD / edge pan, wheel zoom
  HUD.gd               Unit info panel, victory/defeat overlay
  MainMenu.gd          Title screen UI (built in code)
  campaign/            M2 campaign map (#70):
    CampaignState.gd     Province/turn/combat rules -- pure logic, unit-tested
    CampaignLoader.gd    Loads + validates a campaign map from a JSON data file (#125)
    Campaigns.gd         Registry of available campaigns (what the menu lists)
    CampaignMap.gd       Renders provinces, handles clicks, runs the enemy turn
    CampaignHUD.gd       Turn banner, End Turn, standings, victory overlay
data/campaigns/        Campaign map data files (gallic_war.json) -- add a JSON + a
                       Campaigns.gd row to ship a new campaign
assets/                CC0 art goes here (see ASSETS.md) -- not required to run
```

## Swapping placeholder art for real sprites
Units currently draw themselves in `Unit.gd`'s `_draw()`. To use real CC0 art, add a
`Sprite2D` child in `Unit.gd._ready()` pointing at a texture in `assets/sprites/`, and
remove the token-drawing lines from `_draw()` (keep the strength bar / selection ring).
See [ASSETS.md](ASSETS.md) for where to get CC0 medieval sprites.

## Cloud development (Claude Code on the web)

The repo works well with Claude Code's cloud environment for editing GDScript and managing Git, with a few things to know:

**No setup needed for code editing.** The environment requires no environment variables and no build step -- just open a session and start editing.

**Running Godot headlessly is possible** but requires installing it in the setup script. Add this to your environment's setup script (use Godot 4.7.x, or whatever version matches the project):

```bash
wget -q https://github.com/godotengine/godot/releases/download/4.7-stable/Godot_v4.7-stable_linux.x86_64.zip -O /tmp/godot.zip
mkdir -p "$HOME/.local/bin/"
unzip -q /tmp/godot.zip -d "$HOME/.local/bin/"
mv "$HOME/.local/bin/Godot_v4.7-stable_linux.x86_64" "$HOME/.local/bin/godot"
chmod +x "$HOME/.local/bin/godot"
rm /tmp/godot.zip
export PATH="$HOME/.local/bin:$PATH"
```

Once installed, `godot --headless` validates the project and runs the unit-test
suite ([GUT](https://github.com/bitwes/Gut)) -- see [`test/README.md`](test/README.md).

> **Note:** The snippet above targets Godot 4.7 to match the project. If the engine version changes, update both the download URL and the binary filename.

**To actually play the game**, pull the branch locally and open it in the Godot 4.7 desktop editor -- the cloud environment has no display.

## Local checks (reproduce CI before pushing)

[`tools/check.sh`](tools/check.sh) runs the same gating checks as CI so you can
catch failures without waiting on the runners:

```sh
tools/check.sh            # default: validate (import) + GUT tests + doc char-check
tools/check.sh test       # just one (or several) named checks
tools/check.sh all        # add the lychee link-check (if lychee is installed)
tools/check.sh --list     # list the available checks
```

It vendors GUT on demand (it isn't committed), so a fresh checkout needs no
setup beyond a Godot 4.7 binary on `PATH` (or set `GODOT_BIN`). See
[`tools/README.md`](tools/README.md) for details.

## Roadmap

- **M1:** one playable tactical battle.
  ✅ shipped and under continuous development
  (formations, per-soldier combat, morale, fog of war, deterministic replays).
- **M2:** campaign map -- provinces, characters, turn-based diplomacy.
  🚧 in progress: data-driven conquest maps (the Gallic War, The Four Kingdoms)
  with army moves, an enemy AI, war/peace/truce diplomacy, and victory.
  Characters and dynasties are follow-ups.
- **M3:** integration -- armies on the map launch into the battle scene and return a result.
  🚧 in progress: a player attack on a defended province launches the tactical battle
  and applies the outcome to the campaign.
  AI-initiated battles still auto-resolve.

`PLAN.md` carries the detail.
Open work is tracked as `P0`-`P3` issues.

## License

The **code** is licensed under the [MIT License](LICENSE).

**Bundled assets are licensed separately.** MIT covers the source code, *not* the
third-party art and audio under `assets/`, which each keep their own license
(CC0 or CC-BY). See [`assets/sfx/CREDITS.md`](assets/sfx/CREDITS.md) for audio and
[`ASSETS.md`](ASSETS.md) for graphics. The project bundles only assets that permit
redistribution -- never `NC`/`ND` or no-redistribution stock content.
