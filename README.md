# Budget

Een persoonlijke iOS-app om je uitgaven en budgetten bij te houden. Je installeert hem via je eigen AltStore-source op GitHub.

## Wat de app doet

- **Overzicht:** wat je deze maand hebt uitgegeven, per categorie een balk met hoeveel budget je nog hebt, en ongeveer hoeveel je nog per dag kunt uitgeven.
- **Snel invoeren:** tik op *Uitgave toevoegen*. Het toetsenbord opent meteen, je kiest een categorie (de laatst gebruikte staat al geselecteerd) en de datum staat op **vandaag**. Met *Gisteren* of de kalender kies je een andere dag.
- **Snelle actie:** houd het app-icoon ingedrukt en kies **Nieuwe uitgave**.
- **Uitgaven:** per maand, gegroepeerd per dag, met zoeken. Tik op een uitgave om hem te bewerken, veeg naar links om hem te verwijderen.
- **Instellingen:** categorieën toevoegen, bewerken en sorteren (naam, budget, kleur, icoon), en een CSV-export voor Excel of Numbers.
- Alles wordt lokaal opgeslagen met SwiftData. Er is geen account of server.

Vereist iOS 17 of nieuwer.

---

## Eenmalig instellen

### 1. Zet de code op GitHub

1. Maak op github.com een nieuwe repository, bijvoorbeeld `budget`. Kies **Public**: AltStore kan alleen bestanden downloaden uit een openbare repo. Alleen de code is dan zichtbaar, je financiële gegevens niet. Die staan op je telefoon.
2. Upload alle bestanden uit deze map, **inclusief de verborgen map `.github`**. Die staat er misschien niet tussen als je de bestanden via de website sleept. Het makkelijkst gaat het via de terminal:

   ```bash
   cd budget-app
   git init -b main
   git add .
   git commit -m "Eerste versie"
   git remote add origin https://github.com/<jouw-gebruikersnaam>/budget.git
   git push -u origin main
   ```

   Je kunt ook GitHub Desktop gebruiken. Of maak het workflowbestand op de website met *Add file → Create new file*, met als naam `.github/workflows/release.yml`, en plak de inhoud erin.

### 2. Bouw de eerste versie

1. Ga in je repo naar het tabblad **Actions**.
2. Kies links **Build & publiceer** en klik op **Run workflow**.
3. Laat versie `1.0.0` staan en klik op de groene knop.
4. Na ongeveer 5 tot 10 minuten staat er een release met `Budget.ipa`, en is `apps.json` aangemaakt.

Dit kan ook vanuit de GitHub-app op je iPhone.

### 3. Voeg de source toe in AltStore

Open AltStore, ga naar **Sources**, tik op **+** en vul in:

```
https://raw.githubusercontent.com/<jouw-gebruikersnaam>/budget/main/apps.json
```

Daarna staat **Budget** in AltStore en kun je hem installeren.

---

## Een update uitbrengen

1. Pas de code aan en push naar `main`.
2. Start de workflow opnieuw met een **hoger** versienummer, bijvoorbeeld `1.1.0`, en vul in wat er nieuw is.
3. AltStore toont de update. Je gegevens blijven bewaard, want de bundle-ID blijft hetzelfde.

## Goed om te weten

- Met een gratis Apple ID moet AltStore de app elke 7 dagen verversen. Dat doet hij automatisch als AltServer bereikbaar is. Je gegevens blijven daarbij gewoon staan.
- **Verwijder je de app, dan ben je je gegevens kwijt.** Maak dus af en toe een export via *Instellingen → Exporteer uitgaven (CSV)*.
- Wil je de naam, beschrijving of bundle-ID aanpassen? Doe dat in `project.yml` en bovenin `scripts/update_source.py`. De bundle-ID moet in beide bestanden hetzelfde zijn.

## Lokaal ontwikkelen (optioneel, op een Mac)

```bash
brew install xcodegen
xcodegen generate
open Budget.xcodeproj
```

## Bestanden

| Pad | Wat |
|---|---|
| `Budget/` | Swift-broncode en assets (icoon, accentkleur) |
| `project.yml` | XcodeGen-configuratie waaruit het Xcode-project wordt gemaakt |
| `.github/workflows/release.yml` | Bouwt een niet-ondertekend `.ipa`, maakt een release en werkt `apps.json` bij |
| `scripts/update_source.py` | Schrijft de AltStore-source |
| `icon.png` | Icoon voor de AltStore-source |
| `apps.json` | Wordt door de workflow aangemaakt, niet zelf bewerken |
