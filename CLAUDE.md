# FableFlux

Native iOS RSS-lezer met AI-samenvattingen via de Claude API. Heette tot 1.11.0 RSSReader; de lokale
projectmap, de bundle-ID, de Keychain-service en het URL-scheme `rssreader://` houden bewust de oude naam (#145).

**Vereisten:** iOS 17+, Xcode 15+, Swift 5.9+

**Bouwen:** SweetPad in VS Code (zie *Toolchain*), of open `FableFlux.xcodeproj` in Xcode → `⌘R`

## Toolchain
**BELANGRIJK:** dit project gebruikt **SweetPad**, niet XcodeBuildMCP. Deze sectie vervangt de
`## XcodeBuildMCP Integration`-sectie uit de bovenliggende `CLAUDE.md`; gebruik in dit project
geen `mcp__xcodebuildmcp__*`-tools.

- **Build/run/debug:** SweetPad (VS Code) of `xcodebuild` via de terminal.
- **Scheme:** `FableFlux` — het Xcode-project wordt gegenereerd uit `project.yml` (XcodeGen).
- **Code-intelligence:** SourceKit-LSP heeft een `buildServer.json` nodig (niet in Git):
  ```bash
  brew install xcode-build-server xcbeautify
  xcode-build-server config -project FableFlux.xcodeproj -scheme FableFlux
  ```
- **Aanbevolen VS Code-extensies:** zie `.vscode/extensions.json`.
- **Prestaties meten op het toestel:** zie `docs/meten-op-toestel.md` (`xctrace` met `--launch`).

### Bouwen voor een fysiek apparaat
Laat de buildoutput **buiten de projectmap** vallen. Die staat in iCloud Drive;
bouw je naar `build/` binnen de projectmap, dan faalt codesign met *"resource fork,
Finder information, or similar detritus not allowed"*. Twee werkende opties:
`-derivedDataPath` naar een pad buiten de projectmap (zo doet stap 9 van
`Workflow-feature.md` het), of de vlag weglaten zodat xcodebuild
`~/Library/Developer/Xcode/DerivedData` gebruikt. Volg je stap 9, houd dan
`-derivedDataPath` aan: de installatiestap daar verwacht `$DERIVED`.
Simulatorbuilds hebben er geen last van (die worden niet ondertekend).

## Architectuur
- `FableFlux/Models/` — SwiftData-modellen (Feed, FeedItem, MastodonAccount, Topic)
- `FableFlux/Views/` — SwiftUI-views per scherm
- `FableFlux/Services/` — businesslogica (parsing, refresh, clustering, Keychain)
- `AppConfiguration.swift` — centrale constanten en configuratiesleutels

Geen externe Swift-packages; uitsluitend Apple-frameworks en de Anthropic REST API (`claude-haiku-4-5`). API-sleutel wordt opgeslagen in de Keychain via `KeychainService`.

## Bekende valkuilen
- **Zwevende iOS 26-navigatiebalk (#63, #215):** in `ItemDetailView` reserveert het systeem geen ruimte voor de navigatiebalk — die zweeft als een losse capsule bovenop de inhoud. Een nieuw element dat als eerste in de `VStack` staat (vóór de video/audio-player of het web-artikel) tekent zich anders achter de statusbalk/notch. Gebruik `AppConfiguration.floatingNavBarClearance` als topmarge, en pas 'm **maar op één plek** toe — zet je een strip (zoals `TagEditorStrip`) vóór de bestaande inhoud, maak dan de bestaande marge daar conditioneel (`showsTopStrip`) anders krijg je een dubbele, te grote marge.
- **`.swift-format`-configbestand (`orderedImports`):** sommige (nieuwere, lokaal via Xcode geïnstalleerde) `swift-format`-versies eisen dat *alle* sleutels van een deels ingevuld configobject aanwezig zijn, anders breekt elk bestand met "missing key". Vul een object als `orderedImports` altijd volledig in (zie `Documentation/Configuration.md` van swift-format voor de defaults), ook als een deel ervan voor dit project niet relevant is.
- **CI draait alleen op `pull_request`, niet op een directe push naar `main`** (`.github/workflows/ci.yml`). Een hotfix rechtstreeks op `main` wordt dus niet automatisch geverifieerd door de build-check — verifieer in dat geval lokaal of via een losse PR.

## Swift best practices en richtlijnen
@IOS_Swift.md

## Versiebeheer
@Versiebeheer.md

## Workflow feature afronden
@Workflow-feature.md
- Voer deze workflow automatisch en volledig uit zodra de gebruiker aangeeft dat een feature af, klaar of gereed is — of vraagt om te committen na afgerond featurewerk.
