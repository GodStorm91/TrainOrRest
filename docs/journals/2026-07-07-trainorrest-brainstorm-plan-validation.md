# Journal: TrainOrRest brainstorm → plan → validation

- Date: 2026-07-07
- Session type: brainstorm + fast-mode planning + validation interview (no implementation)
- Repo state: greenfield, zero commits

## What happened

Full design cycle for TrainOrRest, a personal iOS app: sync Garmin data, generate race training plans from a goal, daily train-or-rest verdict, Claude coach chat.

1. **Brainstorm** (`plans/reports/brainstorm-260707-1736-garmin-ai-run-coach-ios-report.md`): problem-first inversion applied; 8 decisions captured via structured questions.
2. **Plan** (`plans/260707-1736-trainorrest-garmin-ai-run-coach/`): 4 sequential phases scaffolded via `ck plan create`, fast mode (brainstorm stood in for research). Tasks #1–4 hydrated with blockedBy chain.
3. **Validation**: 4-question interview, 0 verification failures (greenfield — nothing to fact-check against), decisions propagated to phases 1–3, consistency sweep clean.

## Key decisions and why

- **HealthKit over Garmin official API**: Garmin developer program needs business approval — wrong risk for a personal tool. Garmin Connect already syncs to Apple Health. Trade-off: lose proprietary Training Load/Status metrics.
- **Hybrid plan engine**: deterministic generator + `PlanValidator` invariants (ramp ≤10%, taper, quality spacing, available-days); LLM only explains and proposes — proposals must pass the validator. LLM never writes the schedule.
- **Full daily plan regeneration** — user's explicit choice over my bounded-adjust recommendation; risk accepted, mitigated by a determinism + stability contract (unchanged inputs → identical plan; readiness perturbs current week only) plus no-oscillation tests and a diff view.
- **Direct Claude API from app** (key in Keychain, default `claude-sonnet-5`): no backend at all — YAGNI for single user.
- Validation added: configurable weekly availability (days/week + long-run day) into goal + generator, morning verdict local notification into phase 3, paid Apple Developer account for provisioning.

## Impact

- Next step is `/ck:cook` on phase 1 (Xcode bootstrap + HealthKit sync). No code exists yet.
- The `PlanValidator` is the load-bearing artifact: generator correctness, regen stability, and chat guardrails all hang off it. Test it hardest.
- Phase 1 carries an empirical spike: verify what Garmin Connect actually writes to Apple Health on the user's device before building mapping logic.
