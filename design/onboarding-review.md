# TrainOrRest first-run onboarding review

Reviewer: Claude Opus 4.8 (`claude -p --model claude-opus-4-8`), against the first prototype. Later HTML revisions already absorbed several items.

## Verdict

**Revise.** The spine is correct and the voice is mostly on brand. Bans are respected: no em dash, no hype words, no medical or AI-as-authority tone. First-timer guess risks: Coach steps reading as a sequence, Watch Push appearing untaught, Health skip silently removing receipts, feasibility only showing the happy path.

## Applied after review

- Coach instructions now follow the selected provider.
- Watch Push is a control on the intervals form, not a surprise on the success screen.
- Health skip states the cost: session without readiness receipts.
- Feasibility has On track / Stretch / Too soon.
- Completed Today reuses the same setup cards as empty Today.
- Running days has a why. Target time has a format hint.
- North-star headline kept: PRODUCT.md / DESIGN.md own "What should I do in the next 12 hours?"

## Flow issues (Opus, severity order)

1. Coach steps implied "do all three" when one provider is enough.
2. Watch Push appeared on the success screen without being taught.
3. Skipping Apple Health quietly removed the receipts promise.
4. Feasibility showed only On track.
5. Race and feasibility shared one progress notch.
6. Onboarding must write to the same stores as Settings.
7. Completed Today dropped the setup cards that empty Today has.

## What to keep

- Spine: Health, then race, then plan, then optional watch / calendar / Coach.
- Honest time estimate. Optional pipes can wait.
- Health permit list. Google OAuth-not-URL framing.
- Later / Back on optional screens.
- Today receipts line as the payoff.

## Open questions

1. Calendar name is `RestOrTrain Training` in code while the product is TrainOrRest. Keep until an explicit rename.
2. Watch Push is a real Settings toggle, separate from the Garmin "Upload planned workouts" tick.
3. Without Health, Today is plan-only: "Following plan. Readiness unavailable."
4. Re-entry exists in Settings, the calendar status row, and Coach. Completed Today now also carries the cards.
5. Athlete ID lives on intervals.icu Settings. API key is generated in Developer Settings on that same Settings page.
