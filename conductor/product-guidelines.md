# Product Guidelines: Sparta

## 1. Voice, Tone & Documentation Standards
- **Voice & Tone:** Clear, technically precise, and mechanics-focused. Documentation explains the `"why"` behind physical mechanics and architecture without fluff.
- **Typography & Formatting:** Plain-ASCII punctuation only in all documentation and code. Straight quotes (`'` and `"`), ASCII hyphens (`-` or `--`), and standard ASCII characters (no curly quotes or en/em dashes).
- **Code Comments:** Do not cite issue numbers (e.g., `#123`) in code comments; explanations must stand on their own. Reference issue numbers only in commit messages, PR descriptions, and `TODO`/`FIXME` tags.

## 2. Measurement & Units Conventions
- **Units of Measure:** Author length and speed constants in metres (`<metres> * WorldScaleRef.WU_PER_M`).
- **Storage & Sim:** Store all runtime state in world units.
- **Display:** Render user-facing distances and scale through `DistanceLegend` in metric units.

## 3. UI/UX Principles
- **Clarity & Readability:** Battlefield UI prioritizes instant readability of tactical state (unit morale, numbers, facing, unit type badges).
- **Color Coding:** Consistent color language: Blue (Player army), Red (Enemy army), faded alpha for routing units.
- **Controls & Input:** Standard RTS conventions (LMB click/drag selection, RMB move/attack orders, WASD/edge pan, scroll-wheel zoom).
- **Transparency:** Clear tactical feedback for disengaging, flanking impacts, charge blunting, and rout cascades.

## 4. Assets & Licensing
- **Art Licensing:** Strict adherence to CC0 assets (Kenney, OpenGameArt). Never use copyrighted commercial game assets.
- **Procedural & Fallback Graphics:** Core tactical simulation operates cleanly with placeholder/procedural vector tokens before textured sprites.
