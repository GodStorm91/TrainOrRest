# Journal: Phase 1 HealthKit Sync Foundation — Code Complete

- Date: 2026-07-08
- Session type: code mode (`/ck:cook`) on validated phase plan
- Repo state: greenfield; first code written

## What happened

Executed Phase 1 in full: SwiftUI iOS 17+ app with SwiftData, XcodeGen project config, HealthKit sync engine, background delivery, and unit tests. Code builds clean, 13/13 tests pass, all code review findings fixed.

## Environment friction

Xcode 26.6 and iOS 26.5 are not ready for fresh clones:
- CoreSimulator plugin broken; required `-runFirstLaunch` flag to unlock simulator
- 8.5 GB iOS platform download; session resume killed mid-flight on first attempt
- Second download resumed from cache and completed

First simulator test run produced one transient test failure (unrelated to code). Re-run: all pass. No runtime crashes.

## Key architecture

**Pure mapping layer** (`SampleMapping.swift`): Garmin HealthKit data → SwiftData models without HealthKit knowledge. Testable in unit tests with fixtures; logic isolated if Garmin write behavior changes empirically.

**Anchored sync for workouts, 60-day rolling recompute for wellness** — deviation from original "anchored per type." Sleep aggregates daily overlapping samples; recompute idempotent. Code reviewer evaluated and explicitly accepted the trade-off.

**Observer registration at app init** (not view `.task`): This was the most painful fix. Observer in view lifecycle never runs on HealthKit background launches, silently defeating background delivery. Moved to `TrainOrRestApp.init()` so background triggers re-register. Completion waits for sync finish.

## Review and fixes

Code review (code-reviewer subagent): 4 Major + 3 Minor findings. Majors fixed:
1. Observer registration timing (above)
2. Completion handler fired before sync finished
3. Early workouts missing HR (7-day backfill query added)
4. Navigation API anti-pattern

All deferred minors (unbounded import, timezone shifts, error text in UI) marked for v2 with rationale; acceptable for personal tool on greenfield.

## Remaining

On-device verification with real Garmin data requires: paid Apple Developer team (provisioning), setting `DEVELOPMENT_TEAM` in Xcode or env, device with Garmin Connect active sync. Success criteria: real runs/wellness appear, no duplicates on relaunch, background delivery logs visible, correct Garmin source name prefix detected.

---

Status: DONE_WITH_CONCERNS
Summary: Phase 1 code complete and tested; environment tooling friction consumed setup time but resolved. All code review findings fixed. On-device verification spike remains blockers.
Concerns/Blockers: Garmin's exact HealthKit write behavior (source names, distance statistics, HRV cadence) is empirical — must run on user device to confirm mapping logic.
