# TestFlight via Xcode Cloud — openstaande actie

**Status:** besloten, nog niet geconfigureerd. Vervolgstap moet op de MacBook (Xcode-koppeling kan niet op Linux).

## Besluit
FableFlux via **TestFlight** laten lopen in plaats van rechtstreeks installeren via kabel/MacBook.
Build & upload gebeurt via **Xcode Cloud**, niet via de bestaande GitHub Actions-pipeline.

Reden: GitHub Actions (`ci.yml`) draait al op `macos-latest` voor PR-checks en verbruikt daarmee
macOS-minuten; Xcode Cloud heeft een eigen, apart gratis budget van 25 compute-uren/maand
(inclusief in het Apple Developer Program, €99/jaar — geen extra kosten). Xcode Cloud regelt
signing (certificaat + provisioning profile) ook automatisch, GitHub Actions zou dat handmatig
vereisen. Beide pipelines blijven naast elkaar bestaan: GitHub Actions voor PR-build/test-checks,
Xcode Cloud alleen voor de TestFlight-upload (trigger op bv. een tag of push naar `main`).

## Voorwaarden (al voldaan)
- Apple Developer Program-lidmaatschap — aanwezig.
- Git-repo (GitHub) — aanwezig.
- `.xcodeproj` wordt via XcodeGen gegenereerd en blijft in sync met `project.yml`
  (al geborgd door CI-stap "Gegenereerd project is actueel").
- Geen secrets nodig in de build: de Anthropic API-sleutel wordt pas runtime door de gebruiker
  in de Keychain gezet, niet ingebakken tijdens build.

## Nog te doen (op de MacBook, eenmalig in Xcode)
1. App Store Connect-record voor FableFlux aanmaken (bundle-ID, naam, SKU) als dat nog niet bestaat.
2. In het Xcode-project: **Automatically manage signing** aanzetten, zodat Xcode Cloud
   certificaat/provisioning profile zelf kan regelen.
3. `Info.plist`: `ITSAppUsesNonExemptEncryption` expliciet instellen (waarschijnlijk `NO`),
   anders blijft elke upload hangen op "Missing Compliance" omdat niemand de vraag interactief
   kan beantwoorden in een geautomatiseerde pipeline.
4. Xcode Cloud-workflow configureren (Xcode → Product → Xcode Cloud / Report-navigator):
   - Repo autoriseren (GitHub-app-koppeling, eenmalige Apple-autorisatie).
   - Workflow: archive-actie, trigger op tag of push naar `main`.
   - Automatisch build-nummer (`CFBundleVersion`) laten ophogen in de workflow-instellingen.
5. Interne testgroep aanmaken in App Store Connect → TestFlight, jezelf toevoegen als tester
   (eigen Apple ID) — geen Beta App Review nodig voor interne testers (max. 100).
6. TestFlight-app installeren op de iPhone (vereist iOS 17+, voldoet al), uitnodiging accepteren.

## Aandachtspunten
- Builds verlopen na 90 dagen in TestFlight — bij stilstand opnieuw uploaden.
- Externe testers (indien ooit nodig) vereisen Beta App Review (uren tot ~15 uur wachttijd,
  medio 2026); voor eigen gebruik is interne testgroep voldoende en instant.
