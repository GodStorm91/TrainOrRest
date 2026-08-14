# TrainOrRest Redesign Proposal

## 1. Core thesis
The Today screen answers exactly one question: **"What should I do in the next 12 hours?"** Everything else is evidence for that answer. The verdict is a *recommendation with receipts*, framed as a sentence, not a score: "**Train — planned: 6×800m.** HRV normal, sleep 7h40, load balanced." The 78/100 numeral demotes to supporting evidence; the number is not the decision, and pretending it is invites the medical-dashboard failure mode.

## 2. Color strategy
Keep the dark cockpit — it's earned and fits the register. But violet is currently brand + selection + sleep + VO2 + primary action; that's five roles for one hue, so it means nothing. New assignments:

- **Violet (#9B7BF0)**: interactive only — buttons, links, selected tabs, focus. Never data.
- **Data series**: single desaturated cyan (#6BB8D6) for all sparklines/charts. Metrics are neutral evidence; coloring them per-metric implies judgment we don't have.
- **Verdicts**: drop the traffic light. Rest is not "bad" — rose punishes the athlete for recovering. Use **one accent per verdict from a non-alarm family**: Train = cyan-teal, Easy = sand, Rest = a calm slate-blue. Rose (#FB7185) is reserved exclusively for genuine errors (sync failed, permission denied).
- **Amber**: staleness/uncertainty only.

## 3. Typography
Go **SF (system) — do not bundle Barlow**. The condensed-width mapping already approximates the look; bundling a font buys brand at the cost of Dynamic Type fidelity, optical sizing, and binary weight. Hierarchy: SF Rounded semibold for the verdict word only (one moment of warmth), SF Pro text styles elsewhere, SF Mono for timestamps/paces. **Eyebrows: maximum two per screen** — the "What's driving this" section header keeps one; every card-level eyebrow (HRV, SLEEP…) becomes a sentence-case `.subheadline` label. Uppercase tracking is a section device, not a labeling system.

## 4. Verdict presentation
**Kill the hero gauge; commit to a verdict banner.** A ring implies a continuous dial the user should optimize — that's the hype-dashboard grammar. Replace with a full-width TorCard: verdict word (large, tinted), one-line rationale, session row inside it ("6×800m @ 5K pace · 45min"), and a "Why?" disclosure expanding the top three drivers inline. Score appears once, small, monospaced: `readiness 78`. Delete ReadinessCardView entirely — two languages is one too many.

## 5. Information architecture
Four tabs, standard iOS tab bar: **Today · Plan · Trends · Coach**. Settings via gear on Today. **Remove the center FAB** — race-goal entry happens ~4 times a year; it's an onboarding/empty-state flow and a button inside Plan, not the app's anthemic action. Coach earns a tab because plan negotiation is a recurring task, but the Today coach entry card shrinks to one quiet row. Streak chip and 🔥: deleted. Streak lives in Trends as a plain stat.

## 6. Guardrails surface
Every AI plan-edit card carries a fixed three-line ledger: **Proposed by coach → Validated ✓ (n rules passed, tappable list) → You approve**. Diffs shown as before/after rows, apply button is explicit ("Apply to week 6"), and applied edits get a persistent "Revert" affordance in Plan for 7 days. The model proposes; the validator certifies; the user commits. This sequence is always visible, never collapsed.

## 7. Uncertainty states
Uncertainty degrades the *confidence*, not the layout. Stale sync (>12h): amber timestamp chip on the verdict card, verdict wording shifts to "Likely train — based on yesterday's data." Missing metric: the driver card stays, shows "No data" with the cause and a fix action — never hidden, never zero-filled. Denied HealthKit: verdict falls back to plan-only mode and says so: "Following plan — readiness unavailable. Enable Health access." The app never pretends to know.
