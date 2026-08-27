# Whole-scene translation: battle AI reads every anchor's relative position

A staged scenario's combat arc is sensitive to the RELATIVE position of every
unit on the field -- including a "safe" anchor unit hundreds of world units
away and outside detection range -- because battle-AI target scoring reads all
enemy positions when it maneuvers. Moving a scenario for more field room is
therefore only a translation when EVERY actor moves together; moving the
fighting units while leaving (or re-anchoring) a distant bystander produces a
different battle, not a moved one.

Measured on the rout-annihilation demo (rout-rally-recover.json, seed 12345)
while re-staging it onto a tall map so the pursuit could not run out of field:

- Translating only the fighting units (spearmen anchor re-anchored elsewhere)
  flipped the arc from a clean ~350 wu chase ground down to the last man into
  an enveloped kill-in-place 13-80 ticks after the rout, with no observable
  casualties while routing -- across ALL 8 seeds tried, so it was the staging,
  not seed chaos.
- Translating the WHOLE scene by exactly +1200, spearmen included, reproduced
  the original chase arc (rout ~tick 1200, annihilation ~tick 2830).

**Do:** translate every actor together, then re-measure the arc before
trusting it; treat the re-measurement as mandatory since bit-level chaos still
shifts tick timings even under an exact translation.

**Don't:** move a subset of a scenario's units (or "tidy" a bystander's
position) and expect the arc to survive; don't read an arc flip after a
partial move as seed chaos -- sweep seeds first, and when every seed agrees,
the staging is the variable.
