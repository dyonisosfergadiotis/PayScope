# WageWise Design System

## Visual Direction
- Editorial productivity UI with atmospheric background and structured surfaces.
- Strong numeric hierarchy for hours/pay values.
- Accent-driven highlights controlled by user theme selection.
- Every screen answers: What happened, what is now, what comes next.

## Tokens
- Spacing scale: 4, 8, 12, 16, 24, 32.
- Corner radii: 12 for controls, 14 for cards.
- Card style:
  - thin material background
  - subtle border using accent opacity
  - consistent internal padding (16)
- Background style:
  - layered gradient + radial accent glow
  - subtle grid texture for timeline/calendar rhythm
- Button style:
  - primary: filled gradient accent with strong contrast
  - secondary: tinted tonal surface with accent outline

## Typography
- Hero headline: `.system(.title2, design: .serif).bold()`.
- Large values: `.system(.title, design: .rounded).bold()`.
- Section titles: `.system(.headline, design: .rounded).semibold()`.
- Supporting text: `.subheadline` / `.footnote`.
- Inline error/help text uses `.footnote` with semantic colors.

## Onboarding
- Splash:
  - gradient orb + app name + short tagline
  - short fade/scale transition to walkthrough
- Walkthrough pages:
  1. Welcome + value bullets
  2. Pay setup with validated input
  3. Workweek setup
  4. 13-week rule explanation and strict toggles
  5. Theme picker
- Progress indicator and large primary CTA.
- Continue disabled until current step is valid.

## Main Screens
- Today:
  - primary day summary card
  - quick actions row
  - week and month summary cards
  - omission/error card when needed
- Calendar:
  - monthly weekday grid
  - compact status marks for type/warning/error
- Stats:
  - week/month switch
  - KPI cards
  - chart (Swift Charts if available) with fallback custom bars
- Settings:
  - editable pay and rule configuration
  - export CSV action
  - onboarding reset for testing

## Accessibility
- Controls maintain minimum touch area.
- Dynamic Type compatible layouts and multiline labels.
- Accessible labels for status badges, toggles, and navigation actions.

## Empty States
- Each major tab has a purposeful message and one clear next action.
- No blank surfaces.
