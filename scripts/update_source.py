#!/usr/bin/env python3
"""Creates or updates apps.json, the AltStore source for this app.

Called automatically by .github/workflows/release.yml.
Edit the app metadata below to change the name or description.
"""
import argparse
import datetime
import json
import os

APP_NAME = "Budget"
BUNDLE_ID = "com.anthony.budget"  # must match PRODUCT_BUNDLE_IDENTIFIER in project.yml
SUBTITLE = "Personal budgets and expenses"
DESCRIPTION = (
    "Track your spending and stay within budget.\n\n"
    "• Budgets per category with progress bars\n"
    "• Quick expense entry, date defaults to today\n"
    "• Monthly and daily overviews\n"
    "• CSV export\n\n"
    "All data stays on your iPhone."
)
TINT = "#239E6B"
MIN_OS = "17.0"
KEEP_VERSIONS = 10
SOURCE_FILE = "apps.json"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, help="owner/repo")
    parser.add_argument("--branch", default="main")
    parser.add_argument("--owner", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--ipa", required=True)
    parser.add_argument("--notes", default="")
    args = parser.parse_args()

    raw_base = f"https://raw.githubusercontent.com/{args.repo}/{args.branch}"
    download_url = f"https://github.com/{args.repo}/releases/download/v{args.version}/{os.path.basename(args.ipa)}"

    if os.path.exists(SOURCE_FILE):
        with open(SOURCE_FILE, encoding="utf-8") as f:
            source = json.load(f)
    else:
        source = {}

    source.update({
        "name": f"{args.owner}'s apps",
        "identifier": f"io.github.{args.owner.lower()}.source",
        "sourceURL": f"{raw_base}/{SOURCE_FILE}",
        "iconURL": f"{raw_base}/icon.png",
        "tintColor": TINT,
    })
    source.setdefault("news", [])
    apps = source.setdefault("apps", [])

    app = next((a for a in apps if a.get("bundleIdentifier") == BUNDLE_ID), None)
    if app is None:
        app = {"bundleIdentifier": BUNDLE_ID, "versions": []}
        apps.insert(0, app)

    app.update({
        "name": APP_NAME,
        "developerName": args.owner,
        "subtitle": SUBTITLE,
        "localizedDescription": DESCRIPTION,
        "iconURL": f"{raw_base}/icon.png",
        "tintColor": TINT,
        "category": "utilities",
        "appPermissions": {"entitlements": [], "privacy": {}},
    })

    new_version = {
        "version": args.version,
        "buildVersion": str(args.build),
        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "localizedDescription": args.notes or "New version",
        "downloadURL": download_url,
        "size": os.path.getsize(args.ipa),
        "minOSVersion": MIN_OS,
    }
    # Newest version first (AltStore treats the first entry as the latest).
    versions = [v for v in app.get("versions", []) if v.get("version") != args.version]
    app["versions"] = ([new_version] + versions)[:KEEP_VERSIONS]

    with open(SOURCE_FILE, "w", encoding="utf-8") as f:
        json.dump(source, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"Updated {SOURCE_FILE} to version {args.version} (build {args.build})")


if __name__ == "__main__":
    main()
