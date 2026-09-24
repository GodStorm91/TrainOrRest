# TrainOrRest contributor start here

![SwiftUI project map](assets/swiftui-project-map.svg)

![Plan guardrails](assets/plan-guardrails.svg)

![Revision timeline](assets/revision-timeline.svg)

![Test coverage map](assets/test-coverage-map.svg)

## Build shape

- Project config: `project.yml` for the iOS 17 app and unit-test target.
- App target: `TrainOrRest/`.
- Tests: `TrainOrRestTests/`.
- Product source of truth: `PRODUCT.md` and `DESIGN.md`.
- Calendar review flow: [AdaptivePlanReviewCoordinator](../../TrainOrRest/Chat/AdaptivePlanReviewCoordinator.swift) stages reviews. [AdaptivePlanReviewSlot](../../TrainOrRest/Views/AdaptivePlanReviewSlot.swift) renders them.

## Mermaid diagrams

- [App lifecycle](app-lifecycle.mmd)
- [HealthKit sync pipeline](healthkit-sync-pipeline.mmd)
- [Model map](model-map.mmd)
- [Workout push reconciliation](workout-push-reconciliation.mmd)
