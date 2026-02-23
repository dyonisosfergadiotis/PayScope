# PayScope 1.x Plan

## Product Decisions
- App name in UI is `PayScope`.
- Core persistence uses SwiftData models: `DayEntry`, `TimeSegment`, `Settings`.
- Date identity for days is normalized to locale start-of-day and stored uniquely.
- Vacation and sick credit uses strict 13-week weekday lookback with no fallback value invention.

## Architecture
- `Models.swift`: SwiftData entities and enums.
- `CalculationService.swift`: deterministic business logic and `ComputationResult`.
- `CSVExporter.swift`: month export pipeline.
- `Theme.swift`: accent/color system.
- UI split by feature:
  - `RootView` routes onboarding vs main app.
  - `Onboarding` screens with inline validation and persisted settings.
  - `MainTabs` for Today, Calendar, Stats, Settings.
  - `DayEditor` sheet for per-day edits and missing-entry creation.

## Calculation Rules Implementation
- Work day seconds:
  - Uses `manualWorkedSeconds` when available.
  - Otherwise sums validated segment durations.
  - Invalid segments return errors; no silent correction.
- Week grouping respects `weekStart`.
- Month grouping uses calendar month boundaries.
- Vacation/sick credit:
  - Previous `N` same-weekday dates (default 13).
  - Missing days only become zero if `countMissingAsZero = true`.
  - If `strictHistoryRequired = true`, any missing reference date returns `.error`.
  - All-zero references return `.warning` with zero value.
- Holiday credit:
  - `.zero` => 0.
  - `.weeklyTargetDistributed` => `weeklyTargetSeconds / scheduledWorkdaysCount`.

## UX and Error Handling
- Errored vacation/sick days are excluded from totals.
- Separate omission card shows errored day count and explicitly states omitted value is not estimated.
- Empty states for every tab.
- Inline validation for onboarding and day editor.

## Test Plan
- Unit tests cover:
  - segment validation
  - worked-seconds computation
  - lookback success/error/missing/zero-warning paths
  - week grouping by week start
  - holiday credit mode behavior

## Build Constraints
- No external dependencies.
- Dynamic Type and dark mode support.
- Accessibility labels on important controls.
