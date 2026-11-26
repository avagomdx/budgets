#!/usr/bin/env python3
"""Maakt of werkt apps.json bij: de AltStore-source voor deze app.

Wordt automatisch aangeroepen door .github/workflows/release.yml.
Pas de APP-gegevens hieronder aan als je de naam of beschrijving wilt wijzigen.
"""
import argparse
import datetime
import json
import os

APP_NAME = "Budget"
BUNDLE_ID = "com.anthony.budget"  # moet gelijk zijn aan PRODUCT_BUNDLE_IDENTIFIER in project.yml
SUBTITLE = "Persoonlijke budgetten en uitgaven"
DESCRIPTION = (
    "Houd je uitgaven bij en blijf binnen je budget.\n\n"
    "• Budgetten per categorie met voortgangsbalk\n"
    "• Snel een uitgave invoeren, datum standaard vandaag\n"
    "• Overzicht per maand en per dag\n"
    "• Export naar CSV\n\n"
    "Alle gegevens blijven op je iPhone."
)
TINT = "#239E6B"
MIN_OS = "17.0"
KEEP_VERSIONS = 10
SOURCE_FILE = "apps.json"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, help="eigenaar/repo")
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
        "localizedDescription": args.notes or "Nieuwe versie",
        "downloadURL": download_url,
        "size": os.path.getsize(args.ipa),
        "minOSVersion": MIN_OS,
    }
    # Nieuwste versie bovenaan (AltStore neemt de eerste als laatste versie).
    versions = [v for v in app.get("versions", []) if v.get("version") != args.version]
    app["versions"] = ([new_version] + versions)[:KEEP_VERSIONS]

    with open(SOURCE_FILE, "w", encoding="utf-8") as f:
        json.dump(source, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"{SOURCE_FILE} bijgewerkt naar versie {args.version} (build {args.build})")


if __name__ == "__main__":
    main()
