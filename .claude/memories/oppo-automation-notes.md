# Opposition Research Automation — PR #699

## Issue #481: Periodically run the oppo skill

Implements scheduled opposition research to identify features demanded by competitor communities.

## Implementation: GitHub Actions Workflow

**File:** `.github/workflows/opposition-research.yml`

The workflow is set up to run the `opposition-research` skill (/oppo) on a periodic schedule using the existing `claude.yml` infrastructure from `d-morrison/gha@v2`.

### Current State

- **Trigger:** `workflow_dispatch` (manual) only
- **Schedule:** Commented out (requires explicit authorization to enable)
- **Schedule (proposed):** Weekly on Mondays at 09:00 UTC (`0 9 * * 1`)

### Enabling the Schedule

To activate automatic weekly runs, uncomment the `schedule:` block in `.github/workflows/opposition-research.yml`:

```yaml
on:
  schedule:
    - cron: '0 9 * * 1'  # Weekly: Mondays at 09:00 UTC
  workflow_dispatch:
```

This requires explicit user approval before merging because it establishes a persistent autonomous agent that runs on a schedule.

### Testing the Workflow

Before enabling the schedule, test the workflow manually:

```bash
gh workflow run opposition-research.yml
```

Or use the GitHub UI: Actions → Periodic Opposition Research → Run workflow.

### Alternative Mechanisms (Not Implemented)

Two other approaches were considered and rejected:

1. **Claude Code Scheduled Agent (CronCreate)**
   - Uses the `schedule` skill / CronCreate MCP tool
   - Sets up a persistent Claude Code agent that runs on cron
   - More flexible but requires MCP server configuration
   - Not suitable for a repo-hosted workflow

2. **Periodic GIA Loop**
   - Integrates opposition-research into the general issue-grab workflow
   - Better for continuous backlog sweeps
   - Not ideal for a standalone, infrequent (~weekly) research task

The GitHub Actions workflow approach was chosen because:
- It integrates seamlessly with the repo's existing claude.yml infrastructure
- It's version-controlled and auditable
- No additional MCP/tool configuration needed
- Simple to test via workflow_dispatch before enabling the schedule

### Prompt Strategy

The workflow invokes `/opposition-research` with a focused prompt that:
- Names the target competitor (Godot game engine, other real-time tactics engines)
- Scopes on-scope features (real-time tactical mechanics, unit control, physics, etc.)
- Specifies the reporting contract (top demands, demand evidence, on-scope/off-scope triage, issue filing)

## Decision Points for User

1. **Enable the schedule?** Uncomment the `schedule:` block to activate automatic weekly runs.
2. **Adjust the schedule frequency?** Change the cron expression (currently weekly Monday 09:00 UTC).
3. **Modify the scope or competitors?** Update the prompt in the workflow.

## Related Skills & Patterns

- `/opposition-research` — mine competitor communities for feature demands
- `/scout-peers` — the mirror: read competitor *code* vs. their *community*
- `/deep-research` — general multi-source research harness (oppo is the focused specialization)
- Issue-first workflow — each approved oppo finding becomes a tracked issue
