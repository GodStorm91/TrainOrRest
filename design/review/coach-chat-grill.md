
## Round 1 — codex
Who is allowed to author each structured block, especially verdict/rule/readiness content, so the UI never renders model-generated claims as engine truth?
Recommended: Only deterministic app services author `EngineVerdict`, `ReadinessRationale`, rule definitions, grounding footnotes, validation ledger state, and diff/apply/revert metadata. Claude may author prose and a `PlanEditDraft` intent, but the client/server must transform it into a validated artifact before any card renders. If validation fails, show it as “couldn’t validate this proposal,” not as a degraded coach suggestion.

**Designer (claude):** Accepted — and it exposes a real gap in v1, which I've fixed. V1 said "the model returns typed blocks; the client renders them." That's wrong for anything engine-owned: it would let Claude author an `EngineVerdict` payload that renders in system dress. The rule is now **the model emits references and intents; the client hydrates artifacts from local stores**.

Concretely: `CoachBlock` is a Swift enum with provenance baked into the type — `.engineVerdict(EngineVerdict)`, `.readinessRationale(...)`, `.validatedProposal(...)` are only constructible from `ReadinessEngine`/`PlanValidator` outputs; the model's decodable schema simply has no cases for them. Claude may emit `.prose(Markdown)`, `.ruleRef("R4")` (client resolves against the local rule catalog — unknown Rn renders as plain text, no token styling), and `.planEditDraft(intent)`, which the validator transforms before any card exists. Failed validation renders as "Couldn't validate this proposal — [reason]" in system voice, composer live. Grounding footnotes stay client-computed from the actual request payload, never model-claimed.

## Round 2 — codex
During streaming, how do we prevent Claude from narrating an unvalidated plan edit or engine claim before the deterministic artifact exists?
Recommended: Buffer any plan-edit or readiness-sensitive claims until validation/hydration completes; stream only neutral prose. Then insert the system-authored card/ledger first, followed by coach commentary grounded to that artifact. If validation fails, show a system inline failure and suppress any model text that implied the edit was valid.

**Designer (claude):** Accepted, with the mechanism made structural rather than semantic — the client can't reliably detect "readiness-sensitive prose" by reading it, so I won't try. The gate keys on block type, per message:

Streaming runs through a `CoachStreamAccumulator` that parses the typed-block stream incrementally. Pure-prose messages stream token-by-token as before. The moment a `.planEditDraft` or `.ruleRef` block opens in the stream, **all prose in that message — including prose already rendered — moves to held state**: rendered text collapses into the shimmer placeholder (an `.opacity`/`.blurReplace` transition, no jarring removal), and nothing more paints until validation/hydration resolves. Then order is fixed: system card first, coach commentary after, anchored to the artifact.

On validation failure, held prose is **discarded, never rendered** — the schema change: `PlanEditDraft` responses require draft-block-first ordering, and commentary arrives in a separate `commentary` field the client only unseals post-validation. So Claude physically cannot narrate an edit the validator hasn't blessed; the transport doesn't carry that ordering.

One cost admitted: prose collapse mid-stream is a visible hitch. Acceptable — it happens only on proposal turns, where a beat of system deliberation *supports* the guardrail story.

## Round 3 — codex
When Garmin/Health/readiness data changes mid-session, what exact staleness policy prevents a reply or plan proposal from looking current while being grounded in an old snapshot?
Recommended: Every coach request binds to an immutable `GroundingSnapshot(id, timestamp, readinessVersion, planVersion)`. Replies display that snapshot in the footnote. If newer readiness/plan data arrives before send, prompt chip/header updates before the request. If it arrives during streaming, finish the reply but mark it “Based on 6:12 AM snapshot · newer data available” with a one-tap “Refresh answer.” Any plan proposal must validate against the latest plan/readiness versions at apply time; stale proposals become “Needs revalidation,” not applicable.

**Designer (claude):** Accepted nearly whole — with one correction and one addition. `GroundingSnapshot(id, timestamp, readinessVersion, planVersion)` is bound at send, immutable per message, shown in the client-computed footnote (this is what round 1's footnote was implicitly missing: version pins, not just labels — fixed).

The correction: "Refresh answer" must not silently regenerate — that reads as the coach changing its story. It sends a visible new user turn ("Re-check with latest data"), producing a new message pinned to the new snapshot. History stays honest; both answers remain inspectable.

The addition: staleness has a UI home already — the pinned context header. When `readinessVersion` advances, the header chip updates live and any snapshot-mismatched proposal banner flips to "Needs revalidation" (`.disabled` Apply, re-run `PlanValidator` on tap). Validation always executes against latest `planVersion` at apply time regardless — the version pin is a display contract; the validator is the enforcement.

## Round 4 — codex
While a proposal is pending and chat remains open, what prevents a follow-up message from accidentally creating, replacing, or applying plan changes when the user only meant to ask about the current proposal?
Recommended: Allow exactly one active `ValidatedProposal(id)` at a time; follow-up chat can reference it for explanation only. Any new plan-edit intent while one is pending must render a system choice: `Keep current` / `Replace proposal` / `Discard both`, with no auto-supersede. Apply requires the visible proposal id, latest revalidation, and explicit user tap.

**Designer (claude):** Accepted, and this kills v1's auto-supersede — that was a real flaw. "Auto-supersede with confirmation" still lets a casually-worded follow-up ("what if I just did tempo Thursday instead?") destroy a validated proposal the user meant to keep; a question and an edit intent are indistinguishable at the language layer, so the resolution must be structural, not inferred.

Fixed design: exactly one active `ValidatedProposal(id)`. While it's pending, any new `.planEditDraft` the model emits is held un-hydrated and renders a system-voice choice card — `Keep current proposal` / `Replace with this` / `Discard both` — no default action, no timeout. Ordinary follow-ups stay pure prose grounded to the pending proposal's id.

Apply remains a single explicit path: the tap lives only on the proposal card itself, carries its `proposalId`, and triggers `PlanValidator` revalidation against latest `planVersion` first (round 3's contract). Chat can never apply; only the card can.

## Round 5 — codex
On the smallest supported iPhone with keyboard up and Large Accessibility text, what exactly stays visible, collapses, or moves so the screen does not become a stack of header + footnotes + chips + banner + composer with one line of actual chat?
Recommended: Keep only three persistent layers: nav title/role, compact verdict chip, and composer. Hide quick replies behind a single `+`/suggestions button after focus or at large text. Context tray becomes an attachment menu. Pending proposal banner is one tappable row above composer. Footnotes wrap into a tappable “Based on snapshot” row only under completed assistant messages. No fixed-height chrome except composer; cards use readable sheets when expanded.

**Designer (claude):** Accepted — v1's stacked chrome fails exactly this test, so the compression contract is now explicit, keyed on `dynamicTypeSize.isAccessibilitySize` and keyboard focus (`@FocusState`):

Persistent layers: nav bar (title + role line, which at AX sizes truncates to just "Coach"), the verdict chip collapsed to a single `ViewThatFits` row ("Rest · R4", timestamp dropped — it lives in the expansion sheet), and the composer. Nothing else is fixed.

Quick-reply strip and context tray merge into one `+` button in the composer's leading slot presenting a `Menu` — on focus at any size, always at AX sizes. Pending proposal becomes one tappable row ("1 proposal · Needs revalidation" when stale) directly above the composer — this replaces, not stacks with, the chip row. Footnotes collapse to one tappable "Based on 6:12 AM" line, unchanged semantics. Cards expand into `.presentationDetents` sheets, never inline at AX — scrolling one card shouldn't cost the whole feed.

## Round 6 — codex
What is the concrete streaming transport contract, so SwiftUI is not trying to infer typed blocks from partial model text or half-valid JSON?
Recommended: Use a server-normalized event stream, not raw model token parsing: `message_start`, `text_delta`, `intent_final(planEditDraft)`, `rule_ref_final`, `validation_state`, `artifact_final`, `message_done`, `message_error`. SwiftUI renders only `text_delta` as prose; any intent/artifact appears only after a complete, schema-valid final event and local hydration/validation. No client regex, no partial JSON recovery, no hidden model-authored cards.

**Designer (claude):** Accepted in shape, corrected in placement: there is no server to normalize on — TrainOrRest calls the Anthropic API directly with the user's Keychain key. So the normalization layer is the client-side `CoachStreamAccumulator` (an actor), sitting below SwiftUI, and it gets typed events for free by using **tool use, not text conventions**: `planEditDraft` and `ruleRef` are declared tools, so the SSE stream already separates them — `text` blocks stream as prose deltas; `tool_use` blocks accumulate via `input_json_delta` and are decoded **only at `content_block_stop`**, schema-validated with `JSONDecoder` against the intent types. No regex, no partial-JSON recovery, ever.

The accumulator emits exactly the recommended enum — `.textDelta`, `.intentFinal`, `.validationState`, `.artifactFinal`, `.messageDone/.messageError` — as an `AsyncStream<CoachStreamEvent>`; the view renders only these. A malformed final tool payload becomes `.messageError` ("Couldn't read that proposal"), system voice — never a degraded card. Round 2's prose-hold gate keys off `.intentFinal`, unchanged.

## Round 7 — codex
What exact pre-send privacy/grounding contract prevents “Health context” from becoming a vague trust-me toggle that over-shares Garmin/Apple Health data or makes replies look better-grounded than they are?
Recommended: Replace the toggle with a compact `Evidence` button/chip showing the actual outbound scope: `Readiness snapshot`, `This week plan`, optional `Workout`, optional `Photo`. Default sends only a deterministic, minimized snapshot summary and rule-relevant signals, never raw HealthKit/Garmin streams. Workout/photo require explicit visible chips; photos strip metadata. Tapping `Evidence` opens a review sheet before send/first use, and the assistant footnote must mirror exactly what was sent.

**Designer (claude):** Accepted — the boolean "health context" toggle was v1's laziest surviving element, and it broke my own grounding story: round 3's footnote promised to mirror the outbound payload, but a toggle gives the user no idea what that payload *is*. Fixed:

The toggle becomes an **Evidence chip row** inside the composer's `+` menu surface (round 5's merged tray): `Readiness snapshot` and `This week plan` on by default, `Workout` and `Photo` only as explicitly attached chips. What "snapshot" means is deterministic — the same minimized `GroundingSnapshot` summary the engine already computes (verdict inputs, rule-relevant signals, versions), serialized by a fixed encoder. Raw HealthKit/Garmin samples never leave the device; there is no code path that sends them. Photos pass through `CIImage` re-encode, stripping EXIF/location.

Tapping the chip opens a pre-send review sheet showing the literal outbound summary — first use mandatory, thereafter on demand. The footnote and the review sheet render from the **same request payload struct**, so mirror-fidelity is structural, not promised.

## Round 8 — codex
What exactly happens when the user taps Stop mid-stream, especially if a tool call or held proposal prose is in flight?
Recommended: Cancel the request and persist only complete, neutral prose blocks already rendered; discard any incomplete tool JSON, held prose, validation state, or draft intent. Mark the assistant bubble “Stopped” with `Resume` and `Ask again` actions. If any plan-edit intent had begun, render no proposal at all unless `intentFinal` and validation had completed before cancellation.

**Designer (claude):** Accepted with one correction: **no `Resume`**. The Anthropic Messages API cannot resume a cancelled SSE stream — "Resume" would actually be a silent re-generation wearing a continuity costume, which violates round 3's no-silent-regeneration rule. The bubble gets a "Stopped" caption and a single **`Ask again`** action, which sends a visible new turn pinned to a fresh `GroundingSnapshot`.

Everything else is already structurally guaranteed by rounds 2 and 6, now made explicit: Stop cancels the `URLSession` task; the `CoachStreamAccumulator` emits a terminal `.messageStopped`, persists only complete streamed prose, and drops any open `tool_use` block before `content_block_stop` — incomplete JSON never decodes, so no intent exists to leak. Held prose (post-`.intentFinal`, pre-validation) is discarded, matching the validation-failure path.

One refinement: if `.intentFinal` landed before Stop, `PlanValidator` (local, deterministic) still runs to completion — the card renders alone, with no coach commentary, marked "Stopped before commentary."

## Round 9 — codex
How do we prevent free-form coach prose from contradicting the deterministic verdict or smuggling actionable training advice outside a validated proposal?
Recommended: For any verdict, readiness, workout, or plan-turn, render an engine-authored “decision spine” first and treat Claude prose as optional explanation only. Claude may not emit workout prescriptions, “you should run/rest,” or plan deltas in prose; those must be `ruleRef` or `planEditDraft` tools. If a response needs actionable advice and no valid artifact exists, suppress the prose and show a system message: “Coach can explain this, but changes need validation first.”

**Designer (claude):** Partially accepted — the decision spine, yes; the prose-suppression clause, no, and I'll hold the round-2 line: the client cannot semantically classify "actionable advice," so I won't ship a heuristic censor that fails silently.

What I adopt: on any verdict/readiness/plan turn, the engine-authored spine renders first — verdict chip with "Engine · R4" tag hydrated from `ReadinessEngine`, never from the model (round 1's provenance enum already guarantees this). Claude's prose renders below, visually subordinate, in bubble dress.

Why suppression is unnecessary structurally: prose is *inert*. Apply lives only on the proposal card (round 4); no words can change the plan. Contradiction costs trust, not safety — so the defense is juxtaposition: a contradicting sentence sits directly under the engine chip that outranks it, plus a system-prompt contract steering prescriptions into `planEditDraft`, enforced by evals, not client regex.

## Round 10 — codex
If Claude prose is “inert” but still user-actionable in practice, what enforceable contract keeps it from becoming a second coach that contradicts the engine?
Recommended: For verdict/readiness/plan turns, Claude cannot return free-form markdown; it returns a constrained `CoachExplanation` schema tied to artifact IDs: `summary`, `evidenceNotes`, `uncertainty`, `askableFollowups`. No workout prescriptions, no “you should run/rest,” no plan deltas in prose. If the answer requires an action, the only valid output is `planEditDraft`; otherwise the client renders a fixed system line: “Coach can explain this, but changes need validation first.”

**Designer (claude):** Partially accepted — I adopt the schema wherever a deterministic trigger exists, and refuse it where it needs the semantic turn-classifier I rejected in round 9. "Verdict/readiness/plan turn" isn't a type the client can compute from free-typed text; a misfiring censor is worse than juxtaposition. But most verdict interrogation isn't free-typed — it's chip and card taps ("Why rest today?", "What changes?"), where the client authored the prompt and knows the turn type. Fix: those requests set `tool_choice` to a `CoachExplanation` tool — `summary`, `evidenceNotes` keyed to snapshot signal IDs, `uncertainty`, `askableFollowups` — rendered as round 3's rationale card; short structured replies, so no streaming lost. Free-typed turns keep streamed prose under the engine spine, held by system-prompt contract plus evals; long-press gains "Flag conflicting advice," feeding those evals. So prose can't coach on the turns that matter most, and can't act anywhere.

## Round 11 — codex
For a free-typed question like “should I swap tomorrow’s intervals for easy miles?”, what deterministic routing prevents streamed prose from answering before validation?
Recommended: Treat any typed turn with plan/readiness context as tool-first: no prose stream until Claude selects `explainOnly` or `planEditDraft`; `planEditDraft` validates into a card, and `explainOnly` renders constrained explanation text with no imperative training prescription.

**Designer (claude):** Accepted — and it amends round 10, because this routing is enforceable without the semantic classifier I refused: don't classify turns, **remove free prose entirely**. Every free-typed send now sets `tool_choice: {type: "any"}` with exactly two tools, `explainOnly` (the `CoachExplanation` schema) and `planEditDraft`. The API itself then emits no text blocks — Claude *must* route before a single word exists. That's deterministic at the transport, not a client heuristic, so my round-9 objection doesn't apply.

Consequences owned: token streaming dies for typed turns — round 6's decode-at-`content_block_stop` rule stands, no partial-JSON recovery to fake it. Mitigation: explanations are short structured cards, and the avatar shimmer covers the wait. Round 2's prose-hold machinery simplifies to a degenerate case: there's no longer prose to hold. `planEditDraft` → validation → card, unchanged; `.prose` survives only inside `explainOnly.summary`, rendered post-validation of nothing — it's inert by round 9.

## Round 12 — codex
After round 11, typed turns no longer stream; what exact latency/error UI replaces streaming so the user never sees a dead wait or a false partial answer when tool routing, JSON decoding, hydration, or validation is slow/fails?
Recommended: Render a single assistant placeholder with deterministic phase labels: “Checking evidence” → “Reading coach response” → “Validating proposal” only when that phase actually starts. Set short timeouts per phase, surface inline retry on the failed user turn, and never render partial explanation/proposal content before `content_block_stop` plus schema validation.

**Designer (claude):** Accepted, with one honesty constraint: phase labels appear only when their phase is *observably* entered — never predictively. Concretely, the placeholder bubble is driven by the same `CoachStreamEvent` enum from round 6: "Checking evidence" on request build (snapshot serialization, pre-send), "Reading coach response" on `message_start`, "Validating proposal" only on `.intentFinal` when the draft tool fired — `explainOnly` turns never show it, so the label doubles as an early signal of *which* turn type is coming. Labels crossfade in the shimmer slot (`.contentTransition(.opacity)`); no fake progress bars.

Timeouts: 10s to `message_start`, 30s to `content_block_stop`, 5s for local validation (it's deterministic — if it exceeds that, something's broken and we say so). Each failure renders on the *user's* bubble as "Not sent · Retry" or "No response · Ask again" per round 4's contract — retry re-pins to a fresh `GroundingSnapshot`. Nothing partial ever paints; the placeholder is the only pre-completion UI.

## Round 13 — codex
Where does the 7-day revert guarantee live after an edit is applied, so it is not lost once the proposal card collapses or scrolls away?
Recommended: Applied edits become a system-authored receipt in the feed and plan history: “Applied · Revert until Aug 22, 2026,” with diff, proposal id, validation versions, and a Revert action. The pending banner disappears, but the receipt remains findable for 7 days; after expiry it becomes read-only. Revert must run deterministic validation too.

**Designer (claude):** Accepted — and it fixes a real gap: v1 defined Apply and forgot that Revert needs a *home*. A chat feed is a terrible sole custodian of a guarantee; scrollback isn't storage.

So the receipt is dual-homed. On apply, the proposal card collapses into a system-authored **AppliedEditReceipt** block in the feed — "Applied · Revert until Aug 22" caption, collapsed diff, `proposalId`, snapshot/plan versions — constructible only from `PlanValidator` output per round 1's provenance enum, so Claude can never fake one. The same receipt renders in the plan screen's history, which is the canonical surface; the feed copy is a pointer, not the source of truth.

Revert is a plan edit like any other: it runs `PlanValidator` against latest `planVersion` (workouts may have completed since), and produces its own receipt in the feed. Post-expiry, the receipt goes read-only with the Revert affordance removed — no disabled-button graveyard.

## Round 14 — codex
When the grounding snapshot lacks enough valid signals or the engine cannot produce a confident verdict, what exact UI state prevents Claude from filling the gap with plausible coaching?
Recommended: Render an engine-authored “Insufficient evidence” decision spine, disable plan-edit proposal affordances for that turn, and force `explainOnly` to cite only available signals plus missing inputs. No rest/train recommendation, no plan diff, no photo/workout interpretation beyond “not enough evidence”; recovery actions are deterministic: connect data, refresh snapshot, attach workout, or ask a non-action explanation.

**Designer (claude):** Accepted — and it's cheap, because the machinery exists. `EngineVerdict` gains an explicit `.insufficientEvidence(missing: [SignalID])` case; the spine chip renders "No verdict · missing HRV, sleep" in system dress, hydrated only from `ReadinessEngine` per round 1's provenance enum. The missing-inputs list is client-computed from the `GroundingSnapshot`, never model-narrated.

Enforcement is transport-level, extending round 11: when the bound snapshot carries `.insufficientEvidence`, the request's tools array simply omits `planEditDraft` — Claude structurally cannot propose, no censor needed. `explainOnly.evidenceNotes` stays keyed to snapshot signal IDs, so it can only cite signals that exist — including an explicitly attached workout, which *is* available evidence; I won't block discussing data the user handed over.

Recovery chips are client-authored quick replies replacing the generated set: "Connect Garmin" (deep-link), "Refresh snapshot", "Attach today's workout." Deterministic actions, zero coaching theater.
