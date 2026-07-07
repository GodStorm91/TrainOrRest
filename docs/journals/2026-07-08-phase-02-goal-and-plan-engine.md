# Journal: Phase 2 Goal and Plan Engine — Code Complete

- Date: 2026-07-08
- Session type: code mode (`/ck:cook`) on validated phase plan
- Repo state: Phase 1 (HealthKit sync) complete

## What happened

Executed Phase 2 in full: pure `PlanEngine` module (VDOT fitness estimation, deterministic race-backward generator, invariant validator, feasibility check, activity matcher), SwiftData goal/plan models, goal-entry UI with live feasibility, plan calendar, and auto-match integration. 40/40 tests pass, zero warnings. Code review: 1 Major + 6 minors fixed; 3 deferred with rationale.

## Key decisions

**Daniels–Gilbert formulas for VDOT** instead of transcribed lookup table: same mapping, zero transcription-error surface, spot-checked against published rows at 2% tolerance (plan's risk-mitigation spot-checks kept).

**Circular weekday spacing** for quality-day placement: guarantees ≥1 recovery day between hard sessions across week boundaries — a subtle gap when Sunday long-run meets Monday quality. Validated globally in property tests.

## The lesson

The 100-iteration seeded property test caught **two real validator bugs** during development, both in partial-first-week interactions with taper checks. Property test rotates anchor weekday across all 7 days; prorated volume made taper look non-monotonic when it was valid. Confirmed clean with 5,000-iteration offline stress run compiled from pure engine. Fixture tests would have missed both.

## Review and fixes

Code review identified one **Major**: goal form's default race date = today → degenerate one-workout plan. Fixed to +12 weeks; validator now requires race date in future. Minors: removed implicit `TimeZone.current` from validator (purity by signature), fixed auto-match failure message, day-toggle guard enforcement, naming cleanup. Deferred: absolute volume anchor for validator (noted for phase-04 chat guardrails, not generator output).

## Environment friction

Xcode replaced with **Xcode 27 beta** mid-session (`/Applications/Xcode-beta.app`). `xcode-select` pointed at CommandLineTools; worked around with `DEVELOPER_DIR` env + PATH prepend for simctl. Consider `sudo xcode-select -s /Applications/Xcode-beta.app` going forward.

## Remaining

On-device verification: enter real goal → eyeball plan calendar and pace bands; sync next Garmin run and verify auto-match marks the workout done. Cold-start path (requires <6 runs) likely untested with user's 8+ weeks synced.

---

Status: DONE_WITH_CONCERNS
Summary: Phase 2 code complete and tested; property-test-driven design caught real validator bugs early. All code review findings fixed.
Concerns/Blockers: Feasibility thresholds (0.15 VDOT/week ramp, +5 cap, 3-point stretch margin) are first-pass; tune after real-world use on device.
