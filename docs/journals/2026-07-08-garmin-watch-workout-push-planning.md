# Journal: Garmin Watch Workout Push — Design & Planning

- Date: 2026-07-08
- Session type: brainstorm + design review + planning (no implementation)
- Repo state: Phase 1–4 complete on `main`; this feature is independent

## What happened

User regenerates the training plan daily. Workouts arrive as prose in the app but still require 5+ minutes of manual entry in Garmin Connect per quality day — and get thrown away the next regeneration. We designed a full pipeline to push generated workouts directly to the Garmin watch.

**Brainstorm phase** (`plans/reports/brainstorm-260708-1808-garmin-workout-push-report.md`): Problem-first framing confirmed the gap is not in-app visualization but the absence of an outbound workout delivery channel. User deserves to open the watch, see today's tempo/interval session with steps + pace, and not redo it manually after the next plan regeneration.

**Channel evaluation**:
- Official Garmin Training API (`developer.garmin.com`): business-only, new sign-ups suspended. Not viable unless they reopen.
- Unofficial Garmin Connect endpoints (python-garminconnect proves they exist): Swift SSO/MFA login is high-friction, breaks without notice, ToS-gray maintenance tax unacceptable.
- FIT file export: Garmin Connect mobile cannot import workout files; USB-to-watch is incompatible with daily regeneration.
- **Chosen: intervals.icu bridge.** User's personal API key → our app POSTs structured workouts to `intervals.icu/api/v1/athlete/{id}/events` (Basic auth, external_id tagging). intervals.icu holds official Garmin Training API access and auto-syncs today+tomorrow to the watch. Sanctioned, regeneration-friendly, free. Trade-off: third-party dependency.

**User decisions** locked in: all planned runs pushed (easy/long as single step, quality days full structure); auto-replace on regeneration.

## Technical pillars

**Structured steps as engine source of truth**: New pure `WorkoutStep` type (role, distance/duration, optional pace band) emitted by `PlanGenerator`; prose `details` rendered FROM steps (single source of truth, DRY). Persisted on `PlannedWorkout` as Codable array. Easy/long = 1 step; tempo = 2 km WU · tempo km @ T pace · 2 km CD; intervals = 2 km WU · N × (1 km @ I pace + jog) · 2 km CD. Race workouts not pushed.

**Thin client pattern**: Mirrors existing `HealthKitService` boundary. Basic auth with Keychain-stored API key. Event schema uses absolute pace targets (min/km) mapped from pace bands.

**Reconciliation push in sync tail**: After readiness pipeline completes, `SyncEngine` reconciles next 7 days — list remote events by external_id, upsert changed, delete orphans. Stateless, idempotent, offline self-heals next sync. Failures log but never block or fail HealthKit sync. Follows the `autoMatch` pattern (failure isolation).

**Settings UI**: ProfileView section for API key + athlete ID entry, enable toggle, last-push status. One-time manual user step on intervals.icu: authorize Garmin, tick "Upload planned workouts".

## Open risk

**Absolute pace DSL syntax unverified.** intervals.icu workout format accepts text DSL (`- 1km 4:20-4:30/km`) or structured JSON (workout_doc). Phase 2 starts with empirical curl probe against current docs; fallback is `% of threshold pace` syntax if absolute min/km is unsupported. This is the only unknowable blocking detail.

## Plan & next steps

Three-phase plan drafted at `plans/260708-1808-garmin-watch-workout-push/`:
1. **Structured Workout Steps** — PlanGenerator refactor, step array persistence, prose rendering.
2. **intervals.icu Client & Workout Serialization** — HTTP client, pace DSL probe, event payload assembly.
3. **Reconciliation Push & Settings UI** — SyncEngine tail, ProfileView integration, error isolation.

Tasks hydrated across phases. No code review gate run yet (user ended session). Ready for `/ck:cook`.

---

Status: DONE
Summary: Brainstorm → design → planning complete; intervals.icu bridge chosen as the only viable low-maintenance outbound channel. Three-phase plan hydrated and ready for implementation.
