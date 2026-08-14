# Journal — DESIGN.md redesign implementation (codex sub-agent)

Date: 2026-07-13
Branch: `feat/design-ui-and-workout-structure`

## What

Implemented the `DESIGN.md` redesign in place via sequential `codex exec` sub-agent passes,
one phase at a time, with human (orchestrator) review of every diff between phases. No Xcode is
installed on this machine (Command Line Tools only), so nothing could be compiled or unit-tested;
verification was by inspection + `swiftc -parse` (run by codex) + symbol/contract grep.

## Phases shipped

1. **Color tokens & role discipline** (`Theme.swift`, `TrainingVisualStyle.swift`, +consumers):
   added `data` (single cyan for all charts), non-alarm verdict tokens `verdictTrain #4EDCC4` /
   `verdictEasy #E4C58A` / `verdictRest #97AEDC`; violet = interactive only, rose = errors only,
   amber = uncertainty only. Retired the green/amber/rose "traffic light" for verdicts.
2. **Verdict banner + deletions** (`VerdictBannerView.swift` new; deleted `ReadinessGauge.swift`,
   `ReadinessCardView.swift`): replaced the ring hero with a recommendation-first banner (word+glyph
   carry meaning, mono `readiness NN` de-emphasized, "Why?" inline disclosure, plan-vs-data conflict
   with "Keep planned session" override, stale-sync "Likely …" wording). Relocated the
   `torWord/torColor/torSubtitle` verdict extension to shared style code.
3. **Navigation** (`RootTabView.swift`, `TodayView.swift`, `TrendsView.swift`, `SettingsView.swift`,
   `PlanCalendarView.swift`): standard 4-tab bar Today · Plan · Trends · Coach; removed the raised
   center "+" FAB; deleted the streak/🔥 chip from Today (moved to Trends as a plain stat); shrank
   the coach entry to a quiet row; Profile reachable from Settings.
4. **AI-trust surface** (`ReceiptSheet.swift` new, `PlanUpdateCard.swift`, `VerdictBannerView.swift`):
   3-chip ledger (Proposed → Validated → Awaits you); tappable Validated chip opens a shared receipt
   sheet listing the local training rules checked; before/after diff wrapped in `ViewThatFits` for
   AX sizes; explicit "Apply to week N" pinned below the diff; banner "Adjusted · rule" tag opens the
   same shared receipt.
5. **Engine — ADDITIVE slice only** (`DailyCheckIn.swift` new, `ReadinessEngine.swift`,
   `ReadinessStore.swift`, `TodayView.swift`, `TrainOrRestApp.swift`, `VerdictContrastTests.swift`
   new): subjective check-in (typed chips, new additive SwiftData model) fed into
   `ReadinessEngine.assess` via a **defaulted** `checkIns:` param so the existing 10 engine tests stay
   green; `ill`→rest, `sore`→+reason, corroborator chips only strengthen an existing wearable flag.
   Added a WCAG contrast test asserting each verdict token ≥4.5:1 on card in dark mode
   (measured train 10.77, easy 11.03, rest 8.19). Existing test files got additive `DailyCheckIn.self`
   schema registrations only — no assertion changes.

## Deliberately NOT done (stopped per HARD-GATE-NO-SIDE-EFFECTS)

These change existing behavior/tests/schema destructively and cannot be verified without Xcode, so
they were left for a build-backed effort rather than shipped blind:

- §5.1 baseline rewrite (60-day rolling median ±1 SD replacing the 7/28-day means) — would change
  `ReadinessEngineTests` outputs and the `DailyReadiness`/`Snapshot` schema.
- §5.3 per-week append-only revision log + baseRevision pinning + inverse-append revert — rewrites the
  plan-mutation pipeline (`WorkoutReplacementCoordinator`, `CoachChatStore`, `PlanRegenerator`).
- §6 Garmin↔HealthKit source precedence — touches `SyncEngine`/`SampleMapping` and their tests.
- Override-threshold widening + 2-day soreness persistence gate (TODO-commented in the engine).

## Verification gap

No local build/test run possible (no Xcode). All "passes" are parse-level + inspection. Before merge:
run the scheme in Xcode, execute `TrainOrRestTests`, and confirm the new SwiftData model migrates
cleanly on an existing store.
