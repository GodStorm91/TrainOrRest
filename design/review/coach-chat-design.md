# Coach Chat — Converged Design

> Outcome of a designer↔grill working session (Claude = main designer, Codex = grill-me reviewer,
> 14 rounds to convergence) for the Coach chat screen of TrainOrRest. Register: **product**, dark
> cockpit, calm/evidence-led. Anchored on best App Store coaching/assistant patterns (Whoop Coach,
> Runna, Oura Advisor, Claude/ChatGPT iOS) minus their hype. Full Q&A in `coach-chat-grill.md`.

## 0. Core job
The screen exists to **interrogate today's train-or-rest decision**. The one thing it must make
effortless: asking "why?" about the verdict and getting a grounded, rule-cited answer in ≤2 taps.
The chat opens **anchored to today** via a pinned context header (see §7).

## 1. Provenance is a type, not a promise (the trust spine)
The model **emits references and intents; the client hydrates artifacts from local stores.** Encode
provenance in the type system so model-authored content can never render in system dress.

```swift
enum CoachBlock {
    case prose(Markdown)                    // model-authored, inert
    case ruleRef(String)                    // model emits "R4"; client resolves vs local catalog
    case planEditDraft(PlanEditIntent)      // model intent; validator transforms before any card
    // engine-owned — NOT decodable from the model's schema:
    case engineVerdict(EngineVerdict)       // only from ReadinessEngine
    case readinessRationale(ReadinessRationale)
    case validatedProposal(ValidatedProposal) // only from PlanValidator
    case appliedEditReceipt(AppliedEditReceipt)
}
```
The model's decodable schema has **no cases** for engine-owned blocks. Unknown `ruleRef("Rn")`
renders as plain text (no token styling). Failed validation → system-voice "Couldn't validate this
proposal — [reason]", composer stays live. Grounding footnotes are **client-computed** from the
actual request payload, never model-claimed.

## 2. Authority boundary, in-conversation
- Delete the "adapting to today's readiness" status line (implies model authority). Replace with a
  static role line under "Coach": **"Explains & proposes · never edits your plan."**
- Structural, not verbal: **prose = coach speech (bubble dress); cards = system-verified artifacts.**
  Verdicts always render with an **"Engine · R4"** tag hydrated from `ReadinessEngine`, never in the
  coach's bubble voice.
- Prose is **inert**: Apply lives only on the proposal card (§5). No words can change the plan.

## 3. Streaming transport (tool-use based, client-normalized)
No server exists (direct Anthropic API with the user's Keychain key), so the normalization layer is a
client-side **`CoachStreamAccumulator` actor** below SwiftUI. Typed separation comes free from **tool
use**, not text conventions:
- `text` blocks → prose deltas; `tool_use` blocks (`planEditDraft`, `ruleRef`, `explainOnly`)
  accumulate via `input_json_delta` and decode **only at `content_block_stop`**, schema-validated with
  `JSONDecoder`. **No regex, no partial-JSON recovery, ever.**
- Emits `AsyncStream<CoachStreamEvent>`: `.textDelta`, `.intentFinal`, `.validationState`,
  `.artifactFinal`, `.messageDone`, `.messageStopped`, `.messageError`. The view renders only these.
- A malformed final tool payload → `.messageError` ("Couldn't read that proposal"), never a degraded card.

## 4. Tool-first routing for plan/readiness turns (no semantic censor)
The client cannot classify "actionable advice" from free text, so **don't try** — remove free prose on
turns that matter:
- **Chip/card-authored requests** (client knows the turn type): `tool_choice` a `CoachExplanation`
  tool → `summary`, `evidenceNotes` (keyed to snapshot signal IDs), `uncertainty`, `askableFollowups`.
- **Free-typed sends with plan/readiness context**: `tool_choice: {type:"any"}` with exactly two tools —
  `explainOnly` (the `CoachExplanation` schema) and `planEditDraft`. The API then emits **no text
  block**; Claude must route before a word exists. Deterministic at the transport, not a heuristic.
- Consequence owned: typed turns don't token-stream; explanations are short structured cards, avatar
  shimmer covers the wait (§9). `planEditDraft` → validation → card.

## 5. Message rendering rules (structured cards are extracted, not composed)
- **Workout** (planned/completed/proposed) → always a card (title, targets, duration, pace band). Never prose-described.
- **Rule citation `Rn`** → inline tappable token inside prose → sheet with the deterministic rule definition. An atom, not a layout.
- **Readiness rationale** → the `CoachExplanation` card (verdict chip + top-3 signals + Rn tokens) on "why" turns; prose otherwise.
- **Plan edit** → always the validated proposal card. No prose-only proposals.
- Max **one card per message**; card precedes any commentary.

## 6. Pending proposal (no composer lock, one active proposal)
- **Drop the composer lock** — locking punishes the interrogation we want. Chat stays open so the user
  can ask about the proposal before deciding.
- Exactly **one active `ValidatedProposal(id)`**. A new `.planEditDraft` while one is pending renders a
  **system choice card** — `Keep current proposal` / `Replace with this` / `Discard both`, no default,
  no timeout, **no auto-supersede**.
- **Apply lives only on the proposal card**, carries its `proposalId`, and re-runs `PlanValidator`
  against latest `planVersion` first. Chat can never apply.
- Collapsed presence: one tappable row above the composer ("1 proposal" / "1 proposal · Needs revalidation").

## 7. Grounding & privacy (Evidence, not a trust-me toggle)
- Every request binds an immutable **`GroundingSnapshot(id, timestamp, readinessVersion, planVersion)`**,
  shown in a client-computed footnote (version pins, not just labels).
- Replace the boolean "health context" toggle with an **Evidence chip row** (in the composer `+` menu):
  `Readiness snapshot` + `This week plan` on by default; `Workout`, `Photo` only as explicit chips.
- "Snapshot" = the deterministic minimized summary the engine already computes (verdict inputs,
  rule-relevant signals, versions). **Raw HealthKit/Garmin samples never leave the device.** Photos
  re-encode via `CIImage` (EXIF/location stripped).
- Tapping the Evidence chip opens a pre-send review sheet (mandatory first use). Footnote and review
  sheet render from the **same request-payload struct** → mirror fidelity is structural.

## 8. Staleness policy
- Snapshot is immutable per message. When `readinessVersion` advances, the pinned header chip updates
  live; any snapshot-mismatched proposal flips to **"Needs revalidation"** (`.disabled` Apply, re-run
  validator on tap). Validation always executes against latest `planVersion` at apply time.
- **No silent regeneration.** "Re-check with latest data" is a visible new user turn pinned to a new
  snapshot; both answers stay inspectable.

## 9. Latency, streaming & error states
- Single placeholder bubble with **honest phase labels shown only when observably entered**:
  "Checking evidence" (request build) → "Reading coach response" (`message_start`) → "Validating
  proposal" (only on `.intentFinal`). Crossfade in the shimmer slot; no fake progress bars.
- Timeouts: 10s→`message_start`, 30s→`content_block_stop`, 5s local validation.
- **Stop** cancels the `URLSession` task → `.messageStopped`; persists only complete streamed prose,
  drops any open `tool_use` block (incomplete JSON never decodes → no leaked intent). If `.intentFinal`
  landed before Stop, validation still completes and the card renders alone ("Stopped before commentary").
  **No "Resume"** (the API can't resume; that would be silent regeneration) — only **`Ask again`**.
- Errors render on the **user's** bubble ("Not sent · Retry" / "No response · Ask again"), re-pinned to
  a fresh snapshot. Kill the red top capsule. Nothing partial ever paints.

## 10. Empty state + quick replies
- Replace `ContentUnavailableView` with a **capability contract**: today's verdict chip + two columns —
  "Ask me" (explain today, compare weeks, review a photo) and "I can propose, you approve" with a
  miniature 3-chip ledger illustration.
- Chips are **context-aware, client-authored**: verdict day → "Why rest today?"; pending proposal →
  "What changes?"; post-run → "How was my tempo?". Three max, first primary.

## 11. Applied-edit receipt (dual-homed; revert has a real home)
- On apply, the proposal card collapses into a system-authored **`AppliedEditReceipt`** block in the
  feed ("Applied · Revert until Aug 22", collapsed diff, `proposalId`, snapshot/plan versions),
  constructible only from `PlanValidator` output.
- The **plan screen's history is canonical**; the feed copy is a pointer. Revert is a plan edit like any
  other (re-validates against latest `planVersion`, emits its own receipt). After 7 days the receipt
  goes read-only — no disabled-button graveyard.

## 12. Insufficient evidence
- `EngineVerdict` gains `.insufficientEvidence(missing: [SignalID])`; spine chip renders "No verdict ·
  missing HRV, sleep" in system dress; the missing list is client-computed from the snapshot.
- Transport-level enforcement: when the bound snapshot is `.insufficientEvidence`, the request's tools
  array **omits `planEditDraft`** — Claude structurally cannot propose. `explainOnly.evidenceNotes` can
  only cite signals that exist (an explicitly attached workout IS available evidence).
- Recovery = client-authored chips: "Connect Garmin" (deep-link), "Refresh snapshot", "Attach today's
  workout." No coaching theater.

## 13. Responsive / accessibility compression contract
Keyed on `dynamicTypeSize.isAccessibilitySize` + keyboard `@FocusState`. Persistent layers only:
nav (title + role, truncates to "Coach" at AX), the verdict chip as a single `ViewThatFits` row
("Rest · R4", timestamp drops to the expansion sheet), and the composer. Quick-reply strip + context
tray merge into one **`+` Menu** in the composer's leading slot (on focus at any size; always at AX).
Pending proposal is one row above the composer (**replaces**, not stacks with, the chip row). Cards
expand into `.presentationDetents` sheets, never inline at AX.

## 14. Rejected anti-patterns
Motivational filler / streak / emoji hype (Whoop/NRC); model-voiced verdicts "I've adjusted your
plan" (Oura's sin); 6+ chip suggestion carousels; decorative gradient cards; fake typing delays /
"Coach is thinking…" theater; timestamps on every bubble (day separators + first-of-session only);
auto-supersede of a pending proposal; a semantic client-side "advice censor" (fails silently — use
transport-level tool routing instead).

---

## Implementation order (suggested)
1. `CoachBlock` provenance enum + tool schemas (`explainOnly`, `planEditDraft`, `ruleRef`) + `CoachStreamAccumulator` actor (§1,§3,§4).
2. `GroundingSnapshot` binding + Evidence chips + review sheet + footnotes (§7,§8).
3. Rendering: engine spine chip, rationale/workout/proposal cards, Rn tokens (§2,§5).
4. Pending-proposal model + choice card + apply/revalidate + AppliedEditReceipt dual-home (§6,§11).
5. Placeholder/phase-label/Stop/error states; remove red capsule + composer lock (§9).
6. Empty-state capability contract + context-aware/recovery chips; insufficient-evidence path (§10,§12).
7. AX compression contract + `+` menu merge (§13).
