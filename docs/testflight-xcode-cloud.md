# TestFlight via Xcode Cloud

**Status:** afgerond. Eerste build staat in TestFlight, interne testgroep is aangemaakt.

## Besluit
FableFlux via **TestFlight** laten lopen in plaats van rechtstreeks installeren via kabel/MacBook.
Build & upload gebeurt via **Xcode Cloud**, niet via de bestaande GitHub Actions-pipeline.

Reden: GitHub Actions (`ci.yml`) draait al op `macos-latest` voor PR-checks en verbruikt daarmee
macOS-minuten; Xcode Cloud heeft een eigen, apart gratis budget van 25 compute-uren/maand
(inclusief in het Apple Developer Program, €99/jaar — geen extra kosten). Xcode Cloud regelt
signing (certificaat + provisioning profile) ook automatisch, GitHub Actions zou dat handmatig
vereisen. Beide pipelines blijven naast elkaar bestaan: GitHub Actions voor PR-build/test-checks,
Xcode Cloud alleen voor de TestFlight-upload (trigger op push naar `main`).

## Voorwaarden
- Apple Developer Program-lidmaatschap — aanwezig (geen extra kosten t.o.v. de bestaande €99/jaar).
- Git-repo (GitHub) — aanwezig.
- `.xcodeproj` wordt via XcodeGen gegenereerd en blijft in sync met `project.yml`
  (geborgd door de CI-stap "Gegenereerd project is actueel").
- Geen secrets nodig in de build: de Anthropic API-sleutel wordt pas runtime door de gebruiker
  in de Keychain gezet, niet ingebakken tijdens build.

## Uitgevoerde stappen (op de MacBook, in Xcode)
1. App Store Connect-record voor FableFlux aangemaakt (bundle-ID, naam, SKU).
2. **Automatically manage signing** aangezet in het Xcode-project — Xcode Cloud regelt
   certificaat en provisioning profile zelf.
3. `Info.plist`: `ITSAppUsesNonExemptEncryption` op `false` gezet (commit `38a3231`).
   App gebruikt alleen standaard-HTTPS en Keychain, dus geen extra encryptie-verklaring nodig.
   Zonder deze zet blijft elke geautomatiseerde upload hangen op "Missing Compliance", omdat
   niemand de vraag interactief kan beantwoorden in een cloud-build.
4. Xcode Cloud-workflow geconfigureerd (repo geautoriseerd, archive-actie, trigger op push naar
   `main`, automatische verhoging van het build-nummer).
5. Eerste upload liep tegen een onvoorziene validatiefout aan: **ITMS-90474** — FableFlux is ook
   een iPad-target en miste `UIInterfaceOrientationPortraitUpsideDown` in
   `UISupportedInterfaceOrientations~ipad`. Opgelost door alle oriëntaties voor iPad te
   ondersteunen (commit `ec9db1d`); iPhone-gedrag blijft ongewijzigd.
6. Interne testgroep aangemaakt in App Store Connect → TestFlight, Peter toegevoegd als tester
   (eigen Apple ID) — geen Beta App Review nodig voor interne testers (max. 100).
7. Eerste build succesvol via Xcode Cloud geüpload en beschikbaar in TestFlight. TestFlight-app
   op de iPhone geïnstalleerd (iOS 17+, voldoet).

## Resultaat
Geen kabel/MacBook meer nodig om een nieuwe build op de iPhone te krijgen: een push naar `main`
triggert Xcode Cloud, die bouwt, ondertekent en naar TestFlight uploadt; de iPhone haalt de
nieuwe build vervolgens zelf op via de TestFlight-app.

## Aandachtspunten
- Builds verlopen na 90 dagen in TestFlight — bij stilstand opnieuw uploaden.
- Externe testers (indien ooit nodig) vereisen Beta App Review (uren tot ~15 uur wachttijd,
  medio 2026); voor eigen gebruik is de interne testgroep voldoende en instant.
- Bij app-structuurwijzigingen (nieuwe targets, apparaatondersteuning) altijd rekening houden met
  extra App Store Connect-validaties zoals ITMS-90474 — deze verschijnen pas bij de eerste
  upload na de wijziging, niet lokaal bij het bouwen.
- **Workflow-trigger controleren na elke herconfiguratie:** Xcode → Product → Xcode Cloud →
  Manage Workflows → Start Conditions → Branch Changes. Is tijdens het instellen per ongeluk op
  een specifieke feature-branch blijven staan in plaats van `main` — merges naar `main` triggerden
  dan geen enkele build, zonder foutmelding. Check dit bij twijfel altijd eerst.
- **Automatische distributie naar de testgroep is geen standaard:** een succesvolle build
  ("Ready to Test", groen vinkje, geen Missing Compliance) verschijnt niet automatisch bij
  testers tot hij aan een interne testgroep is toegevoegd. "Enable automatic distribution"
  is (in de huidige ASC-UI) alleen instelbaar **bij het aanmaken** van een nieuwe groep, niet
  achteraf voor een bestaande groep te wijzigen. Was dat vinkje gemist, dan is een nieuwe groep
  aanmaken met de optie aan simpeler dan zoeken naar een niet-bestaande edit-knop.
