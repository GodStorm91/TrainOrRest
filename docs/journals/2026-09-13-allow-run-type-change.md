# Journal: Allow Run-Type Changes from Edit with Coach

- Date: 2026-09-13
- Session type: bug fix through autoresearch planning, Grok 4.6 interrogation, cook execution
- Repo state: `feat/plan-proposal-load-warnings`, unstaged; plan at `plans/20260913-154422-allow-run-type-change/`

## What happened

A user opened the 13/09 easy run with Edit with Coach and asked for a tempo. The coach answered with three options instead of a proposal, and picking "replace" produced an English refusal, "This proposal targets a different workout." Both were guards standing in front of a real intent. The rule for the fix was that the coach may warn or inform but never block a run-type change.

Four root causes, each verified against source before any edit:

- Classification. A type-change request with a planned-workout attachment classified as `.unspecified`, so `coach_response` stayed available and the model could answer with options. `CoachChatStore.classifyAction` now treats an attached workout plus a named kind plus an edit cue as `.planMutation`, which removes the free-text tool.
- Context date gate. `validateContextualProposal` rejected any change whose day differed from the attached workout, with a hard-coded English message. The candidate engine already validates every change per date, so the gate was deleted along with its string.
- Pace requirement. `WorkoutFactory.validate` threw when a quality zone was built with no pace table. Under six qualifying runs in 28 days meant no tempo was ever possible. Quality work now builds unpaced; the engine attaches a `paceUnavailable` note.
- Watch push honesty. `WorkoutDSL` labelled unpaced quality work "@ T pace" while sending the easy band. It now says "by effort" with no pace label.

## Data shape

`PlanValidator.Issue.Kind` gained `paceUnavailable`, and `isUserOverridableLoadRisk: Bool` became `Severity` with `blocking`, `acknowledge`, `inform`. Blocking throws at prepare, acknowledge needs the Apply-despite-risk tap, inform renders as a note and never gates Apply. `CoachPlanCandidate` carries `loadRisks` and `notes` separately; `PlanUpdateCard` keys its chrome and Apply label on `loadRisks` only. The note copy lives in `CoachLanguage` (en/ja/vi) and has a matching receipt row.

The `qualityTooClose` message also switched from a raw `Date` description ("2026-09-12 15:00:00 +0000") to a local calendar day; the simulator capture surfaced that one.

## Review

Round 1 ran Grok 4.6 plus two Claude reviewers against the plan; Grok took six rounds to agree. Findings folded in: the classification gap, a phase-1 test that depended on phase 2, a fixture whose Friday was already easy (no-op), a `create()` helper ignoring acknowledgement, the fake watch pace, English advisory copy, an en-only `planValidationChecks` count assertion, a tool description claiming paces are always resolved. Dismissed: a test asserting the prompt contains the new sentence (pins source text).

Post-implementation code review returned "correct" with one finding, the throwaway live repro test still in the target. Replaced by `RunTypeChangeTests`: warm start fills the tempo pace, cold start stages an unpaced tempo with a `paceUnavailable` note and no load risk. The first version trapped because the `ModelContainer` was released while its context was still in use; the fixture now returns the container.

## Verification

- Full suite 569 tests, 0 failures.
- Live Anthropic turn on the seeded coach thread, `Đổi buổi này sang tempo`, stages a tempo replacement card on turn one for both warm and cold fixtures.
- Simulator capture (iPhone 17, vi) shows the card, the plain Apply label, the load warning as information, and no refusal.

## Left open

- `PlanValidator.Issue.message` bodies are English at the engine level for every kind, so the warning row body on the card stays English in ja/vi. Titles and the pace note are localized. Separate change.

Status: DONE
Summary: Run-type changes from Edit with Coach always stage; missing pace is a note, not a refusal.
