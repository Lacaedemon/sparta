# Project Workflow

## Guiding Principles

1.  **The Plan is the Source of Truth:** All work must be tracked in `plan.md`
2.  **The Tech Stack is Deliberate:** Changes to the tech stack must be
    documented in `tech-stack.md` *before* implementation
3.  **Test-Driven Development:** Write unit tests before implementing
    functionality
4.  **High Code Coverage:** Aim for >80% code coverage for all modules
5.  **User Experience First:** Every decision should prioritize user experience
6.  **Non-Interactive & CI-Aware:** Prefer non-interactive commands. Use
    `CI=true` for watch-mode tools (tests, linters) to ensure single execution.

## Task Workflow

All tasks follow a strict lifecycle:

### Standard Task Workflow

1.  **Select Task:** Choose the next available task from `plan.md` in sequential
    order

2.  **Mark In Progress:** Before beginning work, edit `plan.md` and change the
    task from `[ ]` to `[~]`

3.  **Write Failing Tests (Red Phase):**

    -   Create a new test file for the feature or bug fix under `test/unit/`.
    -   Write one or more GUT unit tests that clearly define the expected behavior
        and acceptance criteria for the task.
    -   **CRITICAL:** Run the tests and confirm that they fail as expected. This
        is the "Red" phase of TDD. Do not proceed until you have failing tests.

4.  **Implement to Pass Tests (Green Phase):**

    -   Write the minimum amount of application code necessary to make the
        failing tests pass.
    -   Run the test suite again and confirm that all tests now pass. This is
        the "Green" phase.

5.  **Refactor (Optional but Recommended):**

    -   With the safety of passing tests, refactor the implementation code and
        the test code to improve clarity, remove duplication, and enhance
        performance without changing the external behavior.
    -   Rerun tests to ensure they still pass after refactoring.

6.  **Verify Coverage:** Run verification checks (`./tools/check.sh test` or `patch_coverage`).

7.  **Document Deviations:** If implementation differs from tech stack:

    -   **STOP** implementation
    -   Update `tech-stack.md` with new design
    -   Add dated note explaining the change
    -   Resume implementation

8.  **Commit Code Changes:**

    -   Stage all code changes related to the task.
    -   Propose a clear, concise commit message following conventional commits.
    -   Perform the commit.

9.  **Attach Task Summary with Git Notes:**

    -   **Step 9.1: Get Commit Hash:** Obtain the hash of the *just-completed
        commit* (`git log -1 --format="%H"`).
    -   **Step 9.2: Draft Note Content:** Create a detailed summary for the
        completed task. This should include the task name, a summary of changes,
        a list of all created/modified files, and the core "why" for the change.
    -   **Step 9.3: Attach Note:** Use `git notes add -m "<note content>" <commit_hash>`

10. **Get and Record Task Commit SHA:**

    -   **Step 10.1: Update Plan:** Read `plan.md`, find the line for the
        completed task, update its status from `[~]` to `[x]`, and append the
        first 7 characters of the *just-completed commit's* commit hash.
    -   **Step 10.2: Write Plan:** Write the updated content back to `plan.md`.

11. **Commit Plan Update:**

    -   **Action:** Stage the modified `plan.md` file.
    -   **Action:** Commit this change with a descriptive message (e.g.,
        `conductor(plan): Mark task 'Create user model' as complete`).

### Task Correction & Plan Amendment Workflows

When an implemented task or phase requires corrections, amendments, or additions, follow these standard workflows to maintain plan integrity and avoid untracked code drift:

1.  **In-Flight Refinements:** If minor gaps are found while a task is actively
    in-progress (`[~]`), make the adjustments directly in the active
    implementation stream and ensure passing tests before committing.
2.  **Code Review Corrections (`conductor-review`):** If issues are identified
    during or after a code review, instruct the agent to review your changes
    (`conductor-review`). The review agent will automatically append a `Review Fixes` phase
    to `plan.md` so that correction tasks are formally tracked and
    checkpointed.
3.  **Logical State Reversions (`conductor-revert`):** If a task implementation
    is fundamentally flawed or needs to be redone, instruct the agent to revert
    the changes (`conductor-revert`). This safely rolls back associated git
    commits and resets the task state in `plan.md` back to pending `[ ]` to
    allow a clean restart.

### Phase Completion Verification and Checkpointing Protocol

**Trigger:** This protocol is executed immediately after a task is completed
that also concludes a phase in `plan.md`.

1.  **Announce Protocol Start:** Inform the user that the phase is complete and
    the verification and checkpointing protocol has begun.

2.  **Ensure Test Coverage for Phase Changes:**

    -   **Step 2.1: Determine Phase Scope:** Find the Git commit SHA of the *previous* phase's checkpoint.
    -   **Step 2.2: List Changed Files:** Execute `git diff --name-only <previous_checkpoint_sha> HEAD`.
    -   **Step 2.3: Verify and Create Tests:** Confirm corresponding test files exist for modified code.

3.  **Execute Automated Tests with Proactive Debugging:**

    -   Before execution, announce the exact shell command (`./tools/check.sh test`).
    -   Execute the announced command.
    -   If tests fail, begin debugging (maximum of two attempts before escalating).

4.  **Propose a Detailed, Actionable Manual Verification Plan:**

    -   Generate a step-by-step plan that walks the user through the verification process.

5.  **Await Explicit User Feedback:**

    -   Ask the user for confirmation and await approval.

6.  **Identify Target Commit for Report:**

    -   Identify the hash of the last functional commit made during this phase.

7.  **Attach Auditable Verification Report using Git Notes:**

    -   Draft note content and attach with `git notes add -m "<report>" <commit_hash>`.

8.  **Get and Record Phase Checkpoint SHA:**

    -   Update `plan.md` heading with `[checkpoint: <sha>]`.

9.  **Commit Plan Update:**

    -   Commit change: `conductor(plan): Mark phase '<PHASE NAME>' as complete`.

10. **Announce Completion:** Inform the user that the phase checkpoint is complete.

### Quality Gates

Before marking any task complete, verify:

-   [ ] All tests pass (`./tools/check.sh test`)
-   [ ] Code follows project's code style guidelines
-   [ ] Plain-ASCII typography standards maintained
-   [ ] No hard-coded parameter constants (parameters caller-configurable)
-   [ ] Units convention adhered to (metres authored, world units sim, metric legend)
-   [ ] GDScript .uid sidecars committed for new scripts

## Development Commands

### Setup & Import
```bash
# Godot import / headless validation
godot --headless --import
```

### Daily Development & Testing
```bash
# Run unit test suite
./tools/check.sh test

# Full CI gate replication (import, GUT suite, character checks, comments, units, patch coverage)
./tools/check.sh validate test chars comments units patch_coverage
```

### Code Formatting & Linting
```bash
# Format GDScript
gdformat scripts/

# Lint GDScript
gdlint scripts/
```

## Commit Guidelines

### Message Format

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Types

-   `feat`: New feature
-   `fix`: Bug fix
-   `docs`: Documentation only
-   `style`: Formatting, missing semicolons, etc.
-   `refactor`: Code change that neither fixes a bug nor adds a feature
-   `test`: Adding missing tests
-   `chore`: Maintenance tasks
