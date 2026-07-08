# Product

## Register

product

## Users

TrainOrRest is for one serious recreational runner using an iPhone, Garmin Connect, and Apple Health. They open the app around training decisions: checking today's run, understanding readiness, reviewing recent synced data, and asking the coach why the plan changed or whether to adjust it.

## Product Purpose

TrainOrRest turns Garmin-derived HealthKit data into a practical race-training decision tool. It generates deterministic 5K/10K/half-marathon/marathon plans from a goal, updates the current week based on readiness signals, and uses Claude only to explain or propose changes that must pass local validators before the schedule changes.

Success means the runner trusts the app enough to follow today's recommendation, can see what changed and why, and can safely ask for plan adjustments without the AI silently breaking training constraints.

## Brand Personality

Practical, calm, evidence-led.

The product should feel like a sober training cockpit: focused on decisions, respectful of uncertainty, and restrained enough that health and training data remain the center of attention.

## Anti-references

- Generic fitness hype dashboards with oversized streaks, gamified badges, and motivational noise.
- Medical-looking interfaces that make a training suggestion feel like a diagnosis.
- AI chat surfaces that imply the model has authority over the plan without showing guardrails.
- Decorative SaaS card grids, gradient hero treatments, and marketing-page visual grammar inside the app.

## Design Principles

1. Put today's decision first: Train, easy, rest, or the planned workout should be immediately legible.
2. Explain from evidence: readiness, plan phase, recent runs, and sync freshness should support recommendations without overwhelming the runner.
3. Make guardrails visible: AI-suggested plan edits should feel reviewed, validated, and reversible.
4. Prefer calm density over decoration: the app is a daily tool, not a campaign surface.
5. Respect uncertainty: missing data, stale syncs, denied permissions, and API failures need plain recovery paths.

## Accessibility & Inclusion

Target standard iOS accessibility behavior: Dynamic Type, VoiceOver-readable labels, sufficient contrast, reduced-motion compatibility, and state conveyed by text as well as color. The app should remain usable in bright outdoor light and during low-attention moments before or after a run.
