# Coach Chat Redesign — Proposal v1

## 1. Core job

The screen's job is **interrogating today's train-or-rest decision**. The one thing that must be effortless: asking "why?" about the verdict and getting a grounded, rule-cited answer in under two taps. Everything else — plan edits, photo analysis — is secondary. So the chat opens *anchored to today*: a slim, pinned **context header** under the nav bar showing the day's verdict chip (e.g. "Rest · R4 poor HRV trend") with the readiness snapshot timestamp. Tapping it expands the engine's rationale; it is also the grounding anchor every reply cites.

## 2. Authority boundary, in-conversation

Kill the "adapting to today's readiness" status line — it *implies model authority* and is exactly the anti-pattern we banned. Replace with a static role line under "Coach": **"Explains & proposes · never edits your plan."** Reinforce it structurally, not verbally: every assistant message that touches the plan renders inside a card that carries the ledger grammar (Proposed → Validated → Awaits you). The boundary is legible because *the model's words and the system's actions live in visually distinct containers*: prose = coach speech; cards = system-verified artifacts. Verdicts render with an "Engine · R4" tag, never in the coach's bubble voice — Oura Advisor blurs this line; we won't.

## 3. Message rendering rules (committed)

Structured cards are **extracted, not composed**: the model returns typed blocks; the client renders them. Rules:

- **Workout block** (planned/completed/proposed session) → always a card: title, targets, duration, pace band. Never prose-described workouts.
- **Rule citation** (Rn) → inline tappable token `[R4]` inside prose; tap opens a sheet with the rule's deterministic definition. Not a card — citations are atoms, not layouts.
- **Readiness rationale** → card only when the user asks "why" about a verdict: verdict chip + top 3 contributing signals + Rn tokens. Otherwise prose.
- **Plan edit** → always PlanUpdateCard. No exceptions, no prose-only proposals.
- Everything else stays markdown prose. Max one card per message; card precedes prose commentary.

## 4. Responsiveness

Adopt streaming (token-by-token, Claude iOS style) with a three-dot pre-stream shimmer in the coach avatar slot. Send button → stop button during stream (interruptibility is trust). Failure: the user's message stays in the feed with a "Not sent · Retry" affordance on the bubble itself — kill the red top capsule, errors belong where they happened. Cards render only after the full typed block arrives; prose streams.

## 5. Empty state + quick replies

Replace ContentUnavailableView with a **capability contract**: today's verdict chip + two columns — "Ask me" (explain today, compare weeks, review a photo) and "I can propose, you approve" with a miniature 3-chip ledger illustration. Chips are generated from state: verdict day → "Why rest today?"; pending proposal → "What changes?"; post-run → "How was my tempo?". Three chips max, first primary.

## 6. Grounding

Each assistant reply gets one **footnote row**: tiny icons + labels ("Readiness 6:12 AM · Health · Tue workout"). Tap → sheet listing exactly what was attached. One line, muted, no debug dump.

## 7. Pending proposal

Drop the composer lock. Instead: the PlanUpdateCard pins as a **collapsed banner above the composer** ("1 proposal awaiting you") while chat continues — the user should be able to *ask questions about the proposal before deciding*. Locking punished exactly the interrogation we want. Sending a new plan-edit request while one is pending auto-supersedes with confirmation.

## 8. Rejected anti-patterns

- Motivational filler and streak/emoji hype (Whoop/NRC).
- Model-voiced verdicts ("I've adjusted your plan") — Oura's sin.
- Suggestion carousels of 6+ chips; decorative gradient cards.
- Fake typing delays; anthropomorphic "Coach is thinking…" theater.
- Timestamps on every bubble — day separators + first-message-of-session only.
