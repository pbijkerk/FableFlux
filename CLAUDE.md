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

## Swift best practices en richtlijnen
@IOS_Swift.md

## Versiebeheer
@Versiebeheer.md

## Workflow feature afronden
@Workflow-feature.md
- Voer deze workflow automatisch en volledig uit zodra de gebruiker aangeeft dat een feature af, klaar of gereed is — of vraagt om te committen na afgerond featurewerk.
