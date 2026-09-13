# Review brief: TrainOrRest first-run onboarding

Read `design/onboarding.html` as the proposed first-run flow. Review wording and flow only. Do not edit files. Write your review to `design/onboarding-review.md`.

## Product facts you must respect

- Product: TrainOrRest, a sober iOS training cockpit for one serious recreational runner.
- Voice: practical, calm, evidence-led. No fitness hype, no medical tone, no AI-as-authority.
- Aha moment: Today names a real session for a race the athlete entered, then says train / go easy / rest with receipts.
- Current app: HealthKit permission only on first launch. Goal, intervals.icu, Google Calendar, and Coach API keys live in Settings. There is no event picker. A "goal based on an event" means a race: distance, date, target time, running days.
- Google Calendar is OAuth. The app creates a separate calendar named "RestOrTrain Training". It is not a pasted calendar URL.
- intervals.icu needs Athlete ID + API key from Settings → Developer Settings, plus Garmin "Upload planned workouts" or the watch stays empty. Credentials stay in the iPhone keychain.
- Coach needs one provider key (Anthropic or OpenAI), stored on device. The model proposes; local validators check; the athlete applies.
- Copy bans: no em dash, no Elevate / Seamless / Unleash / Empower / Supercharge / Next-Gen / Game-changer. Do not patronize.

## What to judge

1. Can a first-time runner finish the four jobs without guessing?
   - Create a goal from a race event
   - Set up intervals.icu for workout sync
   - Set up Google Calendar
   - Get an AI API key working
2. Is the spine right: Health → race → plan, then optional watch / calendar / Coach?
3. Are skip paths and empty states enough that experienced users are not blocked?
4. Is each screen one job, with why-we-ask next to the field?
5. Rewrite any line that is vague, insider, duplicated, or longer than it needs to be.

## Required output format in design/onboarding-review.md

- Verdict: ship / revise / rethink
- Flow issues, ordered by severity
- Per-screen copy notes with current line → suggested line
- What to keep
- Open questions for the product owner
