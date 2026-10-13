# tools/lib/melee-clips.sh -- the catalog clips tools/ci/melee-outcome-delta.sh runs by
# default. Sourced; not executable on its own.
#
# MELEE_CLIPS is every website catalog clip (website/tools/demo-catalog.sh) in which some
# unit is in enemy contact on its own seed, sampled every 30 ticks over the clip's covered
# range. A clip with no contact has no melee outcome to perturb, and its runs would only
# cost time. Re-derive the list when the catalog gains a fighting clip (tools/README.md,
# "Perturbed melee-outcome delta", has the command).
#
# MELEE_CLIPS_QUICK is the subset (MELEE_DELTA_SUBSET=quick) whose router or casualty
# outcomes flipped when each unit's facing was nudged by 0.0001 rad: the clips where a
# single-seed check is least trustworthy, and a cheap first look at a melee change.

MELEE_CLIPS=(
  showcase
  charge
  support
  group_attack
  pace_modes
  hold_formation
  square
  schiltron
  cycle_charge
  cycle_charge_flee
  rout_rally
  last_unit_rally
  line_relief
  fighting_withdrawal
  plain_move_withdrawal
  passage_of_lines
  cannae_scale
  battle_ai_leaders
  chase
  wedge_charge
  all_out_attack
  trapped_routing
  pin_down
  sweep_routers
  roll_the_line
  knockback_focus
  coast_to_stop
  subcommander_mutual_support
  general_doctrine_reserves
  chase_canter
  spear_standoff
  small_unit_melee
  give_ground
  file_major_reform_contrast
  disengage_step_back
  shield_wall_encirclement
  multiple_engage
  march_to_contact
  brace_vs_unbraced
  move_cancel_on_engagement
  phalanx_holds_ranks
  disengage_sacrifice_rearguard
  disengaged_march_through_contact
  push_stance
  piercing_melee_hits
  knockback_torque_coupling
  spearmen_weapon_switch
  flanking_maneuver
  missile_profile_reach
  ai_honors_fog
)

MELEE_CLIPS_QUICK=(
  spear_standoff
  file_major_reform_contrast
  charge
  showcase
  march_to_contact
  last_unit_rally
)

# melee_clip_selection <clips> <subset>
#
# Prints the comma-separated selection to run: <clips> itself when set, else the named
# subset ("quick"), else every MELEE_CLIPS clip. An unknown subset name fails with exit 2
# rather than falling back to the full list, which would quietly cost ten times the time.
melee_clip_selection() {
  local clips="$1" subset="$2"
  if [ -n "$clips" ]; then
    printf '%s\n' "$clips"
    return 0
  fi
  case "$subset" in
    '') (IFS=,; printf '%s\n' "${MELEE_CLIPS[*]}") ;;
    quick) (IFS=,; printf '%s\n' "${MELEE_CLIPS_QUICK[*]}") ;;
    *)
      echo "error: unknown MELEE_DELTA_SUBSET '$subset' (known: quick)" >&2
      return 2
      ;;
  esac
}
