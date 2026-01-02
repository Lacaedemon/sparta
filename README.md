```markdown
# Total-War-Like Engine — Godot Prototype (singleplayer + multiplayer)

Overview
--------
Minimal Godot 4 prototype scaffold for a Total-War-like engine:
- Real-time battle scene with basic unit movement, formation placeholder, and combat hooks.
- Turn-based campaign scene shell.
- Multiplayer using ENet (server authoritative): host and join, clients send commands, server runs the authoritative tick and syncs state.

Requirements
------------
- Godot 4.1+ (open Godot and open this project folder)
- No extra plugins required for the scaffold.

How it works (high level)
-------------------------
- NetworkManager handles hosting and joining using `ENetMultiplayerPeer`.
- The server runs the battle simulation (fixed timestep). Clients send commands (e.g., move unit) to server via RPC.
- Server broadcasts state updates; clients apply received authoritative positions.
- Campaign scene is turn-based shell; it can request a battle scene to be started (local or network).

Run locally (singleplayer)
--------------------------
1. Open the project in Godot.
2. Open `scenes/Main.tscn` and run.
3. From Main UI you can open Campaign or Battle scenes.

Run locally (multiplayer)
-------------------------
1. Run one instance and press Host (or call NetworkManager.host(port)).
2. Run another instance and press Join with host IP and port.
3. Client can issue move commands (clicks) — these are sent to server; server authoritatively simulates.

Notes & next steps
------------------
- This scaffold focuses on architecture, not final gameplay or visuals.
- Important next features:
  - Add authoritative interpolation / client-side prediction for smooth movement.
  - Add a deterministic tick / replay system for rollback or desync handling.
  - Replace placeholder visuals with animated models or sprites.
  - Implement formation flow-field movement and more advanced AI.
  - Add authentication & NAT punchthrough for internet play if needed.

License
-------
Pick a license you prefer (MIT/Apache-2.0 suggested). This scaffold contains no third-party assets.

Contact
-------
Repo owner / initial author: dem-extra1
```