# Journal — deferred readiness/plan engine work (DESIGN §5.1, §5.3, §6)

Date: 2026-07-13
Branch: `feat/design-ui-and-workout-structure`

## Context

The earlier DESIGN.md redesign shipped the UI + an additive check-in slice but deferred the
behaviour-changing engine work because no Xcode was available to verify it. Xcode 27 (installed as
`/Applications/Xcode-beta.app`, reached via `DEVELOPER_DIR`) unblocked build+test, so the deferred
work was implemented as four verified phases, each dispatched to a `codex exec` sub-agent and then
built + tested + reviewed + committed individually. codex's sandbox could not reach CoreSimulator,
so I ran `xcodebuild test` (iPhone 17 sim) myself after each phase.

## Phases (each its own commit)

- **`0b1ca2c` §5.1 personal-baseline calibration** — 60-day rolling median + population SD baselines,
  3-day recent reading, two-signal confirmation (no single wearable flag downshifts;
  0→train / 1→train+hedged / 2→goEasy / 3+→rest; `hrvLow && acwrHigh`→rest), and a persistence gate
  (volume-cut verdict holds only if ≥2 flags on ≥2 of last 3 days). Additive `hedged` +
  baseline/SD fields on the assessment and `DailyReadiness`. Rewrote `ReadinessEngineTests` (9) to
  assert the new behaviour.
- **`ba0db71` §5.1.4 override feedback + soreness gate** — `RuleOverride` @Model; threshold widening
  `k = min(2.0, 1 + 0.25·floor(n/2))` over the last 14 days per rule; soreness needs 2 consecutive
  days to add a flag. `assess` gains defaulted `overrides:` / `checkInHistory:`. `RuleOverrideTests` (4).
- **`8107857` §5.2/§5.3 reversible coach edits** — `PlanEdit` journal written atomically in
  `confirmReplacement`; `PlanEditStore.revert` inverse-applies within 7 days behind a fresh-diff guard
  (refuses changed/moved/deleted/expired/already-reverted); Plan-tab "Recent coach changes" UI.
  `PlanEditTests` (6). Stale-diff refusal already existed via `WorkoutReplacementFingerprint`, so no
  event-sourced rewrite was needed.
- **`9156318` §6 source precedence** — sleep aggregates all sources (overlap-merged); HRV/RHR/runs keep
  Garmin preference; `SourceResolution` captures the losing source + divergence; additive HRV
  provenance on `DailyWellness`; `assess` gains defaulted `disputedMetrics` (a disputed HRV hedges
  instead of counting/forcing rest); Today HRV card shows a `2 sources` chip → `ReceiptSheet` and amber
  treatment when disputed. Sleep tests updated to assert aggregate-all; new disputed-HRV engine test.

## Verification

Full suite after Phase 9: **204 tests, 1 failure** — the pre-existing, uncommitted
`KeychainStoreTests` (errSecMissingEntitlement under unsigned simulator runs), unrelated to this work.
All engine/UI suites green. Every `assess` change used defaulted params so prior tests stayed valid.

## Notes / entanglement

`SyncEngine.swift` carried pre-existing intervals.icu push wiring; only the Phase-9 HRV-provenance
hunks were staged (via `git add -p`), leaving the push wiring uncommitted with the rest of that
feature. `DESIGN.md §12` updated to a status list.

## Remaining (see DESIGN §12)

Explicit R1…Rn rule table with IDs; AX3/AX5 banner snapshot tests; in-card "Plan changed since this
was proposed" re-diff UX (stale case still surfaces as an error string).
