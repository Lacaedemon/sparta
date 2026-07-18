# The website demo catalog: every gameplay clip embedded on the docs site, one row per
# clip. Sourced (not executed) by both consumers so the list has exactly one home:
#   - website/tools/record-demos.sh   renders each row to an MP4 + poster at deploy time
#   - website/tools/dump-demo-states.sh   dumps each row's per-tick sim state transcript,
#     the content signal .github/workflows/website-demo-diff.yml compares per PR
#
# Each demo: name | source (res://-relative) | fixed_fps | max_frames | width(px) | type.
# type is "replay" (default, DemoRunner.tscn) or "input" (DemoInputRecorder.tscn).
# Replays may be seed-only auto-battles or scripted scenarios with hand-authored orders.
# A clip covers max_frames * (60 / fixed_fps) physics ticks (fixed_fps sets the VIDEO
# frame rate; physics always runs 60 ticks/s — see demos/README.md).
DEMOS=(
  "showcase|demos/showcase.json|30|650|800|replay"
  "clash|demos/clash.json|30|240|640|replay"
  "charge|demos/charge_demo.json|30|400|640|replay"
  "support|demos/support_demo.json|30|400|640|replay"
  "group_attack|demos/inputs/group-attack-distributed.json|30|400|640|input"
  "pace_modes|demos/inputs/pace-modes.json|30|720|640|input"
  "sidestep|demos/inputs/sidestep.json|30|150|640|input"
  "back_step|demos/inputs/backstep.json|30|300|640|input"
  "arrow_nudge|demos/inputs/arrow-nudge.json|30|330|640|input"
  "about_face|demos/inputs/about-face.json|30|300|640|input"
  "wheel|demos/inputs/wheel.json|30|340|640|input"
  "square|demos/inputs/anti-cav-square.json|30|300|640|input"
  "schiltron|demos/inputs/schiltron.json|30|300|640|input"
  "order_distance|demos/inputs/order-distance.json|30|120|640|input"
  "file_doubling|demos/inputs/file-doubling.json|30|300|640|input"
  "file_doubling_asymmetric|demos/inputs/file-doubling-asymmetric.json|30|150|640|input"
  "cycle_charge|demos/inputs/cycle-charge.json|30|650|640|input"
  "cycle_charge_flee|demos/inputs/cycle-charge-flee.json|30|520|640|input"
  "rout_rally|demos/inputs/rout-rally-recover.json|30|300|640|input"
  "last_unit_rally|demos/inputs/last-unit-rally.json|30|650|640|input"
  "morale_recovery|demos/inputs/morale-recovery.json|30|270|640|input"
  "testudo_under_fire|demos/inputs/testudo-under-fire.json|30|300|640|input"
  "shielded_stances|demos/inputs/shielded-stance-visuals.json|30|180|640|input"
  "decel_arrival|demos/inputs/decel-arrival.json|30|300|640|input"
  "line_relief|demos/inputs/line-relief-queue.json|30|300|640|input"
  "passage_of_lines|demos/inputs/passage-of-lines.json|30|110|640|input"
  "stance_order|demos/inputs/stance-order-gesture.json|30|130|640|input"
  "formation_preview_square|demos/inputs/formation-preview-square.json|30|300|640|input"
  "cannae_scale|demos/inputs/cannae-scale.json|60|300|720|input"
  "battle_ai_leaders|demos/inputs/battle-ai-unit-leaders.json|60|720|640|input"
  "back_speed_by_type|demos/inputs/back-speed-by-type.json|30|430|720|input"
  "formation_shift_reverse|demos/inputs/formation-shift-reverse-505.json|30|130|640|input"
  "chase|demos/inputs/chase-attack.json|30|300|720|input"
  "wedge_charge|demos/inputs/wedge-charge.json|30|270|720|input"
  "all_out_attack|demos/inputs/all-out-attack.json|30|200|640|input"
  "trapped_routing|demos/inputs/routing-terrain-pathfinding.json|30|360|640|input"
  "terrain_exact_footprint|demos/inputs/terrain-exact-footprint-lane.json|30|350|640|input"
  "pin_down|demos/inputs/pin-down-attack.json|30|320|640|input"
  "sweep_routers|demos/inputs/sweep-routers.json|30|130|720|input"
  "roll_the_line|demos/inputs/roll-the-line.json|30|270|640|input"
  "multi_click_speeds|demos/inputs/multi-click-speeds.json|30|330|720|input"
  "knockback_focus|demos/inputs/knockback-focus.json|30|400|720|input"
  "coast_to_stop|demos/inputs/idle-speed-friction.json|30|220|640|input"
  "disciplined_march|demos/inputs/disciplined-vs-undisciplined-march.json|30|300|720|input"
  "form_up_modes|demos/inputs/multi-unit-form-up-modes.json|30|400|720|input"
  "parade_ground|demos/inputs/parade-ground.json|30|1150|640|input"
  "all_teams_control|demos/inputs/all-teams-control.json|60|280|720|input"
  "checkerboard_form_up|demos/inputs/checkerboard-form-up.json|30|460|720|input"
  "subcommander_mutual_support|demos/inputs/subcommander-mutual-support.json|60|480|640|input"
  "lateral_pivot_flank_march|demos/inputs/lateral-pivot-flank-march.json|30|400|720|input"
  "general_doctrine_reserves|demos/inputs/general-doctrine-reserves.json|60|900|640|input"
  "echelon_form_up|demos/inputs/echelon-oblique-form-up.json|30|650|720|input"
  "countermarch|demos/inputs/countermarch-exelismos.json|30|560|640|input"
  "wheel_turn|demos/inputs/wheel-turn-oblique-move.json|30|440|720|input"
  "resize_flank_anchor|demos/inputs/flank-anchored-resize.json|30|160|640|input"
  "cavalry_grid|demos/inputs/cavalry-spacing.json|30|270|640|input"
)
