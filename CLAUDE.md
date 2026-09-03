# CLAUDE.md - TrainOrRest

Source-of-truth docs: `PRODUCT.md` (users, purpose, principles) and `DESIGN.md`
(visual and interaction system). Read both before design work. This section
records decisions that resolve gaps or drift between those docs and the shipped
app; where they conflict, this section wins.

## Design Context

### Users

One serious recreational runner on iPhone, with Garmin Connect and Apple Health.
They open the app around a single training decision: what to do in the next
12 hours, why the plan changed, whether to adjust it. Context is low-attention
and often outdoors in bright light, right before or after a run. The job is a
verdict with receipts, not a dashboard to browse. They already trust their own
numbers; the interface must make those numbers legible, never re-brand them.

### Brand Personality

**Practical, calm, evidence-led.** A sober training cockpit. The coach speaks
in plain sentences and defers to evidence and local validators; it never
performs authority or enthusiasm. Emotional target: earned confidence and calm.
Never urgency, celebration, or guilt. No streaks, badges, or motivational copy.

The one sanctioned warmth moment is the coach pet (`CoachPetView`, assets
`coach-pet-*`): it appears **only** while the coach is preparing, analyzing,
building, or streaming a response, and on the success beat of that same
turn. Never on Today's Call, verdicts, empty states, onboarding, or data
surfaces. Reduced motion shows the static frame.

### Aesthetic Direction

- **Light leads.** Light mode (`Theme` light tokens: `#F7F6F2` canvas, near-white
  glass cards, `#11131A` ink, violet `#7C3AED` interactive, verdict family
  `#087A6E` / `#806021` / `#496BA3`) is the primary appearance because the app
  is used in daylight. Dark is a faithful derivative of the same token roles,
  not a separate design. When a decision only works in one mode, fix it for
  light first, then verify dark. This supersedes DESIGN.md's "dark default";
  screenshots and reviews default to light.
- **Color by role, never by mood.** Violet = interactive only. Cyan `data` =
  chart series only, no judgment. Rose `bad` = error only. Amber `warn` =
  uncertainty only. Verdict hues (Train / Go easy / Rest) are a non-alarm
  family used only on the verdict. Blue `endurance` marks long runs so they
  never read as tappable. Meaning is always carried by text as well as color.
- **Typography does the hierarchy.** System SF; SF Mono for numbers; at most
  two uppercase tracked eyebrows (`TorEyebrow`) per screen; one big number per
  screen at most, and never the readiness score as a headline.
- **Calm density, not decoration.** Reference feel: Apple Health / Fitness
  (system-native, data-forward, restrained color) and Garmin Connect / Strava
  (runner-native vocabulary, real density). Anti-references: hype/streak
  fitness dashboards, medical-looking UI, AI-chat-as-oracle, SaaS card grids
  and gradient heroes.
- **Shipped shell is canonical.** Three destinations in the floating Liquid
  Glass dock: **Calendar** (Today's Call lives here), **Chat**, **Profile**.
  DESIGN.md §7's four-tab `Today · Plan · Trends · Coach` layout is
  superseded; do not migrate toward it.
- **Motion** is state-only, 150–250 ms, never choreography.
- **Devices.** iPhone portrait is first-class and drives every design
  decision. iPad and landscape follow size-class rules (`TorLayout`,
  `torReadableColumn`) and must not break, but never originate a decision.
  Never branch on `UIDevice`/`UIScreen`.

### Design Principles

1. **One decision first.** The verdict sentence is the first and largest thing
   on Today's Call; everything else is evidence for it. The readiness number is
   supporting evidence, never the headline.
2. **Every claim one tap from the athlete's own numbers.** No unexplained
   recommendation, no score without its inputs.
3. **Guardrails visible.** AI plan edits look reviewed, validated, and
   reversible: draft → validate → apply → revert is always legible in the UI.
4. **Color has a job or it isn't there.** Roles above are exclusive; a color
   used outside its role is a bug, not a style choice.
5. **Respect uncertainty and low attention.** Stale syncs, denied permissions,
   missing data, and failures get plain recovery paths; layouts survive
   accessibility Dynamic Type, bright light (≥ 4.5:1 contrast, tested), and
   reduced motion.
