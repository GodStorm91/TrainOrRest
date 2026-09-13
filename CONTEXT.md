# TrainOrRest Domain Context

## Purpose

This file names the Chat planning concepts used by the implementation. Product behavior remains specified by `PRODUCT.md` and `DESIGN.md`.

## Core concepts

### Coach turn

One runner submission and its complete lifecycle: durable request capture, local shortcut or provider execution, streamed assistant state, interaction resolution, and any staged plan decision.

A coach turn is not the Chat screen. Draft text, focus, sheets, scrolling, and thread navigation remain view concerns.

### Candidate plan

An immutable, locally constructed result of applying one normalized coach proposal to the current plan in memory. It contains the exact operations to commit, local validation findings, runner-facing diff, warnings, and the plan revision it was built from.

Review and commit use the same candidate. Commit does not rebuild an equivalent plan.

### Plan revision

An opaque, deterministic fingerprint of the active plan and its workouts at a point in time. It detects any intervening plan mutation, including writes outside Chat.

A plan revision is not an event-stream position and does not replace `TrainingPlan` or `PlannedWorkout` as persisted plan state.

### Plan receipt

A durable `PlanEdit` journal entry recording the exact forward and inverse operations committed from one candidate, plus its base and applied plan revisions. A receipt supports the visible seven-day Revert affordance.

Legacy single-workout `PlanEdit` rows remain readable and revertible through their existing safety checks.

### Fresh diff

A replacement candidate constructed from the original proposal after its base revision no longer matches the current plan. It must be shown with the “plan changed” state and explicitly confirmed again. A stale candidate never writes.

## Invariants

- Provider output proposes; deterministic local code constructs, validates, and commits.
- One proposal produces one candidate construction per review attempt.
- Review and commit refer to the same immutable operations.
- A candidate commits only when its base plan revision still matches.
- A stale candidate is re-diffed and requires another Apply action.
- Every committed Chat plan proposal writes one plan receipt.
- Revert applies a receipt’s inverse only when the current state still matches its recorded applied state.
- Multi-operation commits and reverts are all-or-nothing from the runner’s perspective.
- `TrainingPlan` and `PlannedWorkout` remain the source of current plan truth; no event-sourced rewrite is introduced.

## Example dialogue

Runner: “Move Friday’s tempo to Saturday and add an easy 5 km run on Friday.”

Coach turn: decodes the proposal, constructs one candidate from the current plan, validates the complete result, and stages its exact diff.

Runner: taps Apply.

If the plan revision is unchanged, the candidate operations commit and one receipt is recorded. If anything changed, nothing commits; Chat stages a fresh diff and asks for confirmation again.
