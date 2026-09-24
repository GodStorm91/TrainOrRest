# Journal: Adaptive Next-Week Review

- Date: 2026-09-25
- Session type: feature implementation, review, and documentation closeout
- Repo state: branch `feat/adaptive-week-review`, seven commits on `04c171d`

## What happened

The app gained an adaptive next-week review after a finished run and through a manual Calendar action. The review is limited to the next seven days. Provider output proposes only. Local code constructs, validates, and commits changes.

Automatic review is opt-in. A foreground sync settle may record and prepare one review. HealthKit background delivery never starts provider work. A manual action remains available when a provider key exists. A missing key is visible.

## Data shape

`AdaptivePlanReview` persists the trigger, bounded window, phase, proposal, candidate identifier, plan revision, and optional `PlanEdit` receipt identifier. The candidate is immutable. Review and commit use the same candidate. A stale candidate never writes. It becomes a fresh diff that needs another Apply.

Each commit writes one `PlanEdit` receipt with a seven-day Revert. Revert requires an exact state match. Commits are all-or-nothing. There is no event-sourced rewrite. The flow never calls `CoachTools.apply`.

## Review

Grok interrogated the plan for nine rounds and approved round 9. AdaptiveReviewer findings led to rework. AdaptiveReReviewer returned CORRECT. Two P3 gaps were fixed. The final review of the post-critique diff returned CORRECT with one P3. `ChatMessage.appliedAdjustment` had lost its only assertions, so both Chat confirm tests now assert that it equals the committed candidate summary.

The deslop pass found one bug. A failed save in `beginManualReview` left the inserted review and its supersession writes dirty in the shared context. It now rolls back after a failed save, as the other coordinator save sites do.

Impeccable design critique round 1 scored 28/40 with one P1 and three P2 findings. The P1 covered pinned Google Calendar status at accessibility sizes. The P2 findings covered scope, large-type ledger readability, and violet on non-interactive chrome. Round 2 found the P1 unchanged and English ISO summaries. Round 3 scored 40/40 with no findings.

The round 3 snapshot is stored under `.impeccable/critique/`, which is gitignored. Two round 2 checks were rejected as scroll-fold artifacts. One was the landscape dock over the action row. The other was the phone week card starting at the fold. The bottom safe-area inset carries the 82 pt dock clearance, so the content scrolls clear. Static captures cannot scroll. simctl has no touch command, idb is absent, and AppleScript returned -1728. [Measured]

## Verification

- Full suite passed with 652 tests and 0 failures before the fixups were squashed.
- Focused tests passed with 161 tests and 0 failures after the day-label change.
- Full suite passed with 652 tests and 0 failures on the final history.

## Left open

- The change headline uses past tense ("Rested Sep 25") while the plan is still unchanged. The wording predates this branch and Chat shares it.
- Live end-to-end provider verification is manual only.
