# Budget

A simple personal iOS app for tracking expenses against monthly budgets.

## Features

- Monthly overview with per-category budgets and progress bars
- Quick expense entry: the amount field opens right away, the last-used category is preselected, and the date defaults to today
- Expenses grouped by day, with search, editing and swipe-to-delete
- Home Screen quick action: long-press the app icon → **New expense**
- Customizable categories (name, monthly budget, color, icon)
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
