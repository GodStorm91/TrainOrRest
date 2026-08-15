# DESIGN.md — TrainOrRest

> The visual and interaction system for TrainOrRest, a native SwiftUI iOS
> train‑or‑rest coach for one serious recreational runner. Register: **product**
> (design serves the task; the bar is earned familiarity, and the tool should
> disappear into the decision). This document is the source of truth for the
> redesign. It was produced from the existing `dark cockpit` system plus a
> designer↔reviewer design review (10 rounds) and supersedes ad‑hoc styling in
> individual views.

## 1. North star

The app makes **one decision legible: "What should I do in the next 12 hours?"**
The verdict is a *recommendation with receipts* — a sentence, not a score.
Everything else on Today is evidence for that sentence. The 78/100 readiness
number is supporting evidence, never the headline; treating the number as the
goal is the hype‑dashboard failure mode we explicitly reject.

Design principles (from PRODUCT.md), operationalized:

1. **Today's decision first** — verdict banner is the first and largest element.
2. **Explain from evidence** — every claim is one tap from the athlete's own numbers.
3. **Guardrails visible** — AI proposes, a local validator certifies, the athlete commits; that sequence is always on screen.
4. **Calm density over decoration** — no gamification, no gradients as decoration, no eyebrow-on-every-section.
5. **Respect uncertainty** — low confidence changes the *wording*, never fakes a downgraded verdict.

---

## 2. Color system

Keep the **dark cockpit** as the default; it fits a sober daily tool used in
varied light. The fix is *role discipline* — today one hue (violet) means five
things, so it means nothing.

### 2.1 Neutral surface (unchanged tokens, in `Theme.swift`)

| Token | Dark | Light | Role |
|---|---|---|---|
| `bg` | `#08080D` | `#EEEFF3` | app canvas |
| `card` | `#14141D` | `#FFFFFF` | primary surface |
| `card2` | `#1B1B26` | `#F6F6FA` | nested/inset surface (use sparingly; never nest cards in cards) |
| `text` | `#F5F5FA` | `#0C0C14` | ink |
| `dim` | ink @ 62% | ink @ 62% | secondary text — **body copy floor** |
| `faint` | ink @ 46% | ink @ 46% | captions/timestamps only; never body |
| `border` | white @ 8% | ink @ 9% | hairline, 1px |

**Contrast rule:** body text uses `text` or `dim` (≥4.5:1 on `card`). `faint`
is for ≤12pt captions and timestamps only. Never use `faint` for anything a
glancing, mid‑routine athlete must read.

### 2.2 Role colors — one job each

| Role | Token / hex (dark) | Used for | Never used for |
|---|---|---|---|
| **Interactive** | violet `#9B7BF0` / `accent2 #7C5CE0` | buttons, links, selected tab, focus ring, primary action | data, decoration, verdicts |
| **Data series** | cyan `#6BB8D6` (new, desaturated) | all sparklines & charts, one neutral series | conveying good/bad judgment |
| **Error only** | rose `#FB7185` | sync failed, permission denied, validator rejected | the Rest verdict |
| **Uncertainty** | amber `#FBBF24` | stale sync, disputed source, unconfirmed metric | anything healthy |

Metrics are neutral evidence. Coloring each driver a different hue implies a
judgment the app doesn't have; sparklines are all one cyan.

### 2.3 Verdict colors — non‑alarm family (this is the big change)

The traffic light is retired. **Rest is not "bad"** — punishing recovery with
rose is wrong. Verdicts read from a calm, non‑alarm palette, and **color is
only reinforcement — the word + glyph carry the meaning** (honest for the ~5%
of deutan athletes for whom teal/sand collapse, and for VoiceOver).

| Verdict | Word | SF Symbol | Hex on `#14141D` | Contrast |
|---|---|---|---|---|
| Train | "Train" | `figure.run` | `#4EDCC4` | ≈10.9:1 |
| Go easy | "Go easy" | `tortoise` | `#E4C58A` | ≈10.3:1 |
| Rest | "Rest" | `moon.zzz` | `#97AEDC` | ≈7.1:1 |
| Building baseline | "Building baseline" | `chart.line.uptrend.xyaxis` | `dim` | — |

**Contrast is enforced, not asserted:** a snapshot/unit test asserts each
verdict color ≥4.5:1 against `card` so token drift fails CI.
`ReadinessCardView` (the legacy tinted card) is **deleted** — two verdict
languages is one too many.

---

## 3. Typography

**Ship system fonts (SF); do not bundle Barlow.** The condensed‑width mapping in
`Theme.swift` already approximates the display look, and bundling costs Dynamic
Type fidelity, optical sizing, and binary weight for marginal brand gain.

- Verdict word: **SF Rounded, semibold** — the one permitted moment of warmth.
- Everything else: SF Pro text styles (`.largeTitle`→`.caption`), so AX sizes scale correctly and rationale wraps instead of truncating.
- Timestamps, paces, the readiness number: **SF Mono**.
- **Eyebrow budget: two uppercase tracked eyebrows per screen, maximum.** Keep them as *section* devices (e.g. "What's driving this"). Every card‑level eyebrow (`HRV`, `SLEEP`, `RESTING HR`) becomes a sentence‑case `.subheadline` label. Uppercase tracking is not a labeling system.
- Body/prose capped at 65–75ch; data rows may run denser.

---

## 4. Today screen — verdict banner (replaces the hero gauge)

**Retire the ring gauge.** A dial implies a continuous number to optimize —
hype‑dashboard grammar. Replace with a full‑width `TorCard` banner:

```
┌─────────────────────────────────────────────┐
│  figure.run  Train                            │  ← SF Rounded, verdict color
│  Planned: 6×800m @ 5K pace · 45 min           │  ← session inside the banner
│  HRV normal · slept 7h40 · load balanced      │  ← one-line rationale (dim)
│  Why?  ▸                        readiness 78  │  ← disclosure + mono score
└─────────────────────────────────────────────┘
```

- **"Why?"** expands inline to the top three drivers in the athlete's own numbers. No separate modal.
- **Score** renders once, `readiness 78`, SF Mono, untinted, **not tappable**, no delta arrow, no "▲ +4 vs yesterday." Nothing to game.
- Below the banner: the existing "What's driving this" 2‑col grid (HRV, Resting HR, Sleep, VO₂max, Load/ACWR) with single‑cyan sparklines and sentence‑case labels. Streak moves out of Today entirely (see §7).

### 4.1 Plan-vs-data conflict (never averaged away)

When the deterministic plan says "6×800m" but readiness is borderline, the
banner shows **both sides, plus a one‑tap override** — it does not silently pick
one:

- Verdict word `Go easy` (sand); rationale names both: *"Plan calls for 6×800m, but HRV is 12% below baseline."*
- Session row shows the modification: ~~6×800m~~ → "4×800m or easy 40 min," with an `Adjusted · rule` tag.
- A **"Keep planned session"** button lets the athlete overrule in one tap.

### 4.2 Low confidence ≠ downgraded verdict

Staleness/noise **softens wording**, never the verdict: *"Likely train — last
sync 14h ago"* with an amber timestamp chip; the planned session stays
unmodified. The app never pretends to know.

---

## 5. Deterministic adjustments & AI trust surface

Two mutation sources, one shared receipt grammar so provenance is always one tap
away:

### 5.1 Rule adjustments (local, deterministic — Claude never touches the plan)

The plan engine owns a modifier table; the session substitution comes from a
rule, not the model. Every rule‑adjusted row carries an `Adjusted · rule` tag;
tapping opens a sheet with the exact trigger in the athlete's numbers and the
ledger line **"Adjusted by rule R4 — no AI involved."**

Rules must not nag a healthy athlete over device noise. Calibration is
structural:

1. **Personal baseline** = rolling **60‑day median with a ±1 SD band**. The trigger is `HRV < baseline − 1.0 SD` (not a fixed 10%); noisy wearables get wider bands automatically.
2. **Two‑signal confirmation** — a downshift needs a second corroborating signal (resting HR > +5 bpm, or sleep < 6h, or a subjective chip). Single‑metric outliers never downshift alone.
3. **Persistence gate** — one bad morning yields hedged wording; a volume cut needs the signal on 2 of the last 3 days.
4. **Override feedback** — two "Keep planned session" taps on the same rule within 14 days widen that rule's threshold 0.25 SD, logged in the rule sheet.

### 5.2 AI plan-edit cards (coach proposals)

A fixed three‑step ledger, always present as a **single row of glyph+word
chips**: `sparkles Proposed · checkmark.seal Validated · person Awaits you`.

- Validation detail ("n rules passed") lives behind the Validated chip's tap target — the *sequence* is always visible; the detail is one tap.
- Diffs are the content, not chrome: each session diff is one row (day, ~~old~~ → new). On iPhone SE / AX sizes, rows wrap side‑by‑side → stacked via `ViewThatFits`.
- The **Apply** button is pinned at the card bottom *after* the rows — you cannot approve without scrolling past every change. Copy is explicit: "Apply to week 6."
- Applied edits get a persistent **Revert** affordance in Plan for 7 days.

### 5.3 Revision model (prevents stale diffs / clobbering)

Every mutation — coach apply, rule adjustment, manual edit — **appends** to a
per‑week revision log; week state is derived, never edited in place. Each
proposal is pinned to its `baseRevision`. On Apply, if `currentRevision !=
baseRevision`, the apply is refused and the card re‑diffs against current state
with a "Plan changed since this was proposed" banner. No silent rebase; last
approver wins **only after seeing a fresh diff**. Revert is an inverse‑append
(new revision undoing exactly revision N), with the same fresh‑diff
confirmation if later revisions touched the same sessions.

---

## 6. Source conflicts (Garmin vs HealthKit)

Precedence is fixed and deterministic — **Garmin wins for runs & HRV**
(watch/strap‑native), **HealthKit wins for sleep** (aggregates all sources). The
banner always shows one number from the winning source, never an average.

Conflict surfaces as a small `2 sources` chip on the affected **driver card**
(not the banner). Tapping opens the shared receipt sheet: *"HRV: Garmin 52ms
(used) · Apple Health 61ms. Garmin is primary for HRV — change in Settings."*
If divergence exceeds the metric's 1 SD band, that driver card takes the amber
uncertainty treatment and the metric is treated as **unconfirmed** by §5.1's
two‑signal layer — so a disputed HRV alone can't downshift a workout.

---

## 7. Information architecture

Four standard iOS tabs; **no center FAB.**

`Today · Plan · Trends · Coach`

- **Remove the raised "+" FAB.** Race‑goal entry happens ~4×/year — it's an onboarding/empty‑state flow and a button inside **Plan**, not the app's anthemic action. The FAB currently mis‑signals goal entry as the primary verb.
- **Coach earns a tab** — plan negotiation is a recurring task. The Today coach entry shrinks to one quiet row (no gradient avatar hero treatment).
- **Settings** stays behind the gear on Today.
- **Streak + 🔥 chip: deleted from Today.** Gamified streaks are an explicit anti‑reference. Streak survives only as a plain stat in Trends.

### 7.1 Trends

- Cut "best readiness" — a leaderboard/record stat invites gaming. Replace with the **verdict distribution**: "Trained 16 · Easy 5 · Rested 7."
- The 28‑day readiness line stays but is **banded** (normal range shaded), unlabeled by peaks, captioned *"readiness reflects recovery, not effort."* No maxima, no records.

---

## 8. Uncertainty & empty states

Uncertainty degrades **confidence, not layout**:

| State | Behavior |
|---|---|
| Stale sync (>12h) | amber timestamp chip on banner; wording → "Likely train — last sync 14h ago"; planned session unmodified |
| Missing metric | driver card stays visible, shows "No data" + the cause + a fix action; **never hidden, never zero‑filled** |
| HealthKit denied | verdict falls to plan‑only mode and says so: *"Following plan — readiness unavailable. Enable Health access."* |
| Validator rejected an AI edit | rose banner on the coach card: what rule failed, in plain language; the plan does not change |
| Building baseline | verdict = "Building baseline," progress `day n/N`, no fabricated score |

---

## 9. Subjective check‑in (context wearables miss)

A quiet **"Anything to note?"** row on the Today banner before the day's first
session. Fixed chips only — no free text, no severity sliders (chips are typed
signals, not self‑diagnoses): `sore · ill · poor sleep · travel · alcohol ·
stress · heat`.

Rule path into the same engine:
- Most chips (travel, alcohol, stress, heat) are **corroborators only** — they can confirm a wearable anomaly (§5.1 layer 2) but never fire a downshift alone.
- Two carry standalone rules because sensors genuinely miss them: `ill → rest, quality frozen 48h`; `sore (2 consecutive days) → intensity capped`.
- Every chip‑triggered adjustment gets the standard `Adjusted · rule` receipt naming the chip ("You reported illness — rule R7").
- Unused chips still log to the day's record (visible in the driver sheet) — recorded, never decorative. The athlete can always "Keep planned session."

---

## 10. Motion

Product motion: 150–250ms, conveys state only.

- Verdict/state changes: crossfade (existing `.easeOut(duration: 0.2)` is right).
- "Why?" and receipt sheets: standard disclosure/`.sheet`, no orchestration.
- Sparklines/charts: no entrance choreography — the app loads into a decision, not a reveal.
- **Reduced motion:** every transition has a `prefers-reduced-motion` → instant/crossfade path. No bounce, no elastic.

---

## 11. Component inventory (target state)

| Component | Status | Note |
|---|---|---|
| `TorCard` | keep | radius 16–20 for cards; 26 reserved for the verdict banner only |
| Verdict banner | **new** | replaces `ReadinessGauge` hero on Today |
| `ReadinessGauge` (ring) | **remove from Today** | may survive as a small Trends glyph only |
| `ReadinessCardView` | **delete** | legacy tinted card; second verdict language |
| `DriverCard` grid | keep | single‑cyan sparklines, sentence‑case labels |
| Receipt sheet | **new** | shared by rule adjustments, AI edits, source conflicts |
| Coach edit card (3‑chip ledger) | **new/refactor** | replaces free‑floating `PlanUpdateCard` styling |
| Custom tab bar + center FAB | **replace** | standard 4‑tab bar, no FAB |
| `TorEyebrow` | keep, **rate‑limit** | max 2 per screen |
| Streak chip | **delete** from Today | plain stat in Trends |

Every interactive component ships all states: default, hover(N/A on touch),
focus, pressed, disabled, loading (skeleton, not spinner), error.

---

## 12. Status

**Implemented & test‑verified (Xcode 27, iPhone 17 sim):**
- ✅ §5.1 personal‑baseline calibration — 60‑day median ±1 SD, two‑signal confirmation, persistence gate (`ReadinessEngine`).
- ✅ §5.1.4 override feedback — `RuleOverride` widens a rule's threshold 0.25 SD per two overrides in 14 days; soreness needs 2 consecutive days.
- ✅ §5.2/§5.3 reversible coach edits — `PlanEdit` journal + 7‑day inverse‑apply revert with a fresh‑diff guard (stale‑diff refusal already existed via `WorkoutReplacementFingerprint`).
- ✅ §6 source precedence — sleep aggregates all sources; HRV/RHR/runs prefer Garmin; HRV divergence captured as provenance and treated as unconfirmed in the engine, surfaced as a `2 sources` chip → receipt.
- ✅ Subjective check‑in wired into the two‑signal layer; verdict‑contrast test asserts ≥4.5:1.
- ✅ Explicit readiness rule catalog `ReadinessRuleID` R1–R10 (HRV=R4, illness=R7), attached to each assessment and cited in the banner receipt ("Rule Rn · …").
- ✅ Banner Dynamic Type layout tests at AX3/AX5 on iPhone SE width (`VerdictBannerLayoutTests`): content wraps, never overflows 320pt.
- ✅ §5.3 stale coach proposals re‑diff in‑card ("Plan changed since this was proposed") instead of dead‑ending on an error.

**Intentional non‑goals:**
- Full event‑sourced "derived week state" was intentionally NOT built; the `WorkoutReplacementFingerprint` optimistic‑concurrency check plus the `PlanEdit` revert journal deliver the anti‑clobber + reversibility guarantees at far lower risk.

---

*Provenance: synthesized from `Theme.swift` / `TrainingVisualStyle.swift` and the
existing dark‑cockpit source (`design/TrainOrRest.dc.html`), refined through a
10‑round designer↔reviewer design review. Full Q&A transcript retained separately.*
