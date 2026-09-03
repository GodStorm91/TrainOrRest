# Journal: Coach Response Redesign - Code Complete

- Date: 2026-08-31
- Session type: continuation of cook phase execution (phases 8-10 + finalize)
- Repo state: phases 1-7 already implemented; redesign now complete and committed on `feat/design-ui-and-workout-structure`

## What happened

Completed the Coach response redesign. Coach replies are no longer one Markdown wall of text: the reply is a validated, authority-split structured response rendered as a compact card, with a detail sheet, per-message follow-up chips, a source-attribution sheet, and a measured header inset.

This session implemented the final three phases and hardened them through two review cycles.

- Header inset. The message list top inset is now derived from the measured sticky-header height via a `CoachHeaderHeightKey` preference and `CoachHeaderMetrics.messageTopInset(headerHeight:)`, replacing the hardcoded `.padding(.top, 70/72/74)` guesses. The first line clears the header at any Dynamic Type size and in the collapsed state. Full semantic streaming (`CoachResponseStreamEvent`) remains a backend change; the shipped work is the inset.
- Source attribution and accessibility. The card's attribution line ("Dua tren N nguon - Cap nhat <time>") is a 44pt tappable button opening `CoachSourcesSheet`, which lists sources as labels and SF Symbols only, never raw model context. The card title carries an accessibility header trait. `ChatBubble` passes the message date as the card timestamp.
- Model prompt and validation gate. `CoachContextBuilder` instructs the model to emit the structured contract (decision-first title, short summary, up to three recommendations, optional details, up to three follow-ups, optional safety note), respond in the app language, avoid mixed languages and invented units, and not fabricate the app-owned status, metrics, and sources. Validation reuses `validatedStructuredResponse`: title and summary are required or the reply falls back to the legacy text path; recommendations cap to three with overflow moved into a details section; follow-ups cap to three.

## Decisions

- Authority split (locked in phases 1-2, honored here). The model authors only title, summary, recommendations, details, follow-ups, and safety note. The app hydrates status, metrics, and sources deterministically from `DailyReadiness`/`ReadinessRationale` and the request snapshot. The phase-10 prompt therefore does not ask the model for metrics or source IDs; it tells the model the app owns them. The original brief's "model returns metrics and source IDs" would reintroduce the rejected model-authored-engine-truth pattern and is not decodable in the locked schema.
- No fragile post-processing. The mixed-language and unit safeguard is the prompt plus the app formatting all numbers itself, not string replacement of generated text.

## Review cycles

In-house adversarial reviewer, then a cross-model review (Codex, read-only sandbox) under doubt-driven development. Findings were reconciled against the code, not rubber-stamped.

Fixed:

- Attribution time formatted with the device locale instead of the selected app locale (could show "Cap nhat 1:58 PM" in a Vietnamese app). Now formatted with `language.uiLocale` via a testable `CoachResponseCard.updatedTimeText(_:language:)`.
- Model details with an empty or whitespace-only sections array produced a visible "View detailed analysis" button leading to a blank sheet. `validatedStructuredResponse` now drops blank sections and returns nil details when nothing renders.
- Untrusted model output could carry duplicate recommendation, section, or follow-up IDs (a SwiftUI `ForEach` hazard) and blank follow-up label/value pairs. Now deduped by ID (keep-first) and blank entries dropped.
- Tests strengthened: prompt-contract assertions cover each required clause; the full-structured test asserts field preservation and IDs, not only caps.

Documented, not changed:

- The system prompt is built as a static head, then dynamic data is appended and truncated; the contract instructions live in the static head and survive truncation. The store's post-truncation append of the interaction directive is pre-existing and out of this scope.
- Length and count caps beyond the existing three-item limits are a trade-off; the source is our own first-party model, and capping analysis length risks corrupting legitimate long text.
- Hardcoded "Coach" (brand) and the "Run" workout-kind fallback are pre-existing and unrelated to this work.

## Verification

Ran:

```bash
xcodebuild test -project TrainOrRest.xcodeproj -scheme TrainOrRest -destination 'platform=iOS Simulator,name=iPhone 17'
```

Result: 490 tests passed, 0 failures, no unused-symbol warnings. UI phases additionally verified by rendering cards, the detail sheet, follow-up chips, the safety callout, and the source indicator to PNG rasters via `ImageRenderer`, and by reading those images.

## Remaining

- A real Anthropic API key is still needed to verify a live coach turn emits the new structured contract end-to-end and renders as a card.
- This environment has no XCUITest target, so deep UI interaction (tap-through to the sheets, 44pt hit testing, header-frame under live Dynamic Type) is verified by unit tests, code review, and rasters rather than automated UI tests.

---

Status: DONE

Summary: Coach response redesign phases 1-10 complete and committed; structured contract, hydration, persistence, compact renderer, detail sheet, per-message follow-ups, composer and source simplification, measured header inset, attribution and accessibility, and the model prompt plus validation gate all landed with 490 passing tests.

Concerns/Blockers: Live Claude API behavior and on-device UX still need manual verification with the user's API key.
