# Budget

A simple personal iOS app for budgeting from payday to payday.

## Features

- Setup wizard on first launch: pay day, net income, fixed costs and budgets
- Pay periods from payday to payday (e.g. 20 Nov – 19 Dec), with a weekend rule for when salary arrives early or late
- "Left to spend" = income − fixed costs − spent, plus an estimate per day until the next payday
- Fixed costs and savings with weekly, monthly, quarterly or yearly frequencies (only when due, or spread evenly)
- Default income and fixed costs for every new period, editable per period
- Payday check-in to confirm income and fixed costs, optionally carrying over last period's leftover
- "Salary came early" to start the next period today
- Extra income during a period (refunds, Tikkies)
- Category budgets per period, optionally carrying over what's left
- Period history: income, fixed costs, spent, left over and saved
- Quick expense entry: the amount field opens right away, the last-used category is preselected, and the date defaults to today
- Home Screen quick action: long-press the app icon → **New expense**
- CSV export
- All data is stored on the device with SwiftData. There's no account or server.

Requires iOS 17 or later.

## Install with AltStore

Add this source in AltStore (**Sources → +**):

```
https://raw.githubusercontent.com/avagomdx/budgets/main/apps.json
```

## Build locally

On a Mac with Xcode 16 or later:

```bash
brew install xcodegen
xcodegen generate
open Budget.xcodeproj
```

## Releases

The **Build & release** GitHub Actions workflow builds an unsigned `.ipa`, publishes it as a GitHub release and updates `apps.json`. AltStore signs the app when it's installed.

## Project structure

| Path | Contents |
|---|---|
| `Budget/` | Swift source and assets |
| `project.yml` | XcodeGen configuration |
| `.github/workflows/release.yml` | Build and release workflow |
| `scripts/update_source.py` | Generates the AltStore source (`apps.json`) |
| `icon.png` | Icon for the AltStore source |
