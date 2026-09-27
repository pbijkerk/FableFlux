# Workflow: Feature afronden (versiebeheer)

Voer deze stappen in volgorde uit zodra een feature af is. Sla geen stappen over; meld het expliciet als een stap niet kan.

## 1. Controleer de werkstatus
- `git status` — welke bestanden horen bij deze feature?
- Werk op een feature branch (`feat/<korte-naam>` of `fix/<korte-naam>`). Zit je op `main`, maak dan eerst een branch.
- Stage alleen bestanden die bij de feature horen. Nooit: build-output, `.DS_Store`, losse notities of niet-gerelateerde wijzigingen (benoem die wel).

## 2. Build-check
- Draai `xcodebuild` voor de iOS Simulator. De build moet slagen vóór er gecommit wordt.
- Faalt de build: eerst herstellen, daarna verder.
- Gebruik een destination zonder toestelnaam; die hoeft voor een build-check niet:
  ```bash
  xcodebuild -project FableFlux.xcodeproj -scheme FableFlux \
    -destination 'generic/platform=iOS Simulator' build
  ```
- Noem je toch een toestel, geef dan ook `OS=` mee. Zonder die sleutel kiest `xcodebuild`
  `OS:latest`, en dan faalt de build met *"Unable to find a device matching the provided
  destination specifier"* zodra dat toestel niet in de nieuwste iOS-versie bestaat — een
  iPhone 16 kan lokaal alleen als iOS 18.0 bestaan terwijl de nieuwste runtime 26.x is.
  Welke combinaties er zijn: `xcrun simctl list devices available`. Pin geen vaste
  toestel/OS-combinatie vast in documentatie: die verschilt per werkplek en per
  Xcode-installatie.

## 3. CHANGELOG.md bijwerken
- Voeg onder de sectie `## [Unreleased]` één bondige regel toe (Nederlands) onder de juiste kop (`### Toegevoegd`, `### Gewijzigd` of `### Opgelost`).
- Neem dit bestand mee in dezelfde commit.

## 4. Commit
- Conventional Commits: `feat:`, `fix:`, `chore:`, etc.
- Onderwerpregel bondig in het Nederlands; daarna een korte toelichting met opsomming.
- Afsluiten met: `Co-Authored-By: Claude <noreply@anthropic.com>`

## 5. Push en pull request
- `git push -u origin <branch>`
- `gh pr create --base main` met secties **Doel**, **Wijzigingen** en **Verificatie**.

## 6. Review
- Voer `/code-review` uit op de PR.
- Correctheidsbevindingen: eerst oplossen, opnieuw committen en pushen.
- Cleanup-bevindingen: melden aan de gebruiker; alleen uitvoeren op verzoek.

## 7. Merge (alleen na akkoord van de gebruiker)
- Vraag expliciet akkoord voordat je merget.
- `gh pr merge <nr> --merge --delete-branch` (merge-commit, conform de repo-historie).
- Daarna: `git checkout main && git pull`.

## 8. Release (alleen op expliciet verzoek)
- Versie bumpen volgens SemVer: MINOR bij een feature, PATCH bij een fix.
- `## [Unreleased]` in CHANGELOG.md omzetten naar `## [X.Y.Z] - JJJJ-MM-DD`.
- Git-tag `vX.Y.Z` aanmaken en pushen — **pas nadat de release-PR op `main` is gemerged**.
  Tag je daarvoor, dan wijst de tag naar een commit zonder de bump en bouw je een oude versie.
  Controleer het met `git show vX.Y.Z:project.yml | grep MARKETING_VERSION`.
- Voer nooit een release uit zonder expliciete bevestiging (zie Versiebeheer.md).

## 9. Installeren op de iPhone (alleen na een release, stap 8)
- Hoort bij stap 8 en deelt dus dezelfde gate: alleen uitvoeren als er daadwerkelijk een release
  is uitgebracht. Na gewoon featurewerk (stap 1–7) niets installeren.
- Zonder App Store-distributie is een release pas af als de nieuwe versie op het toestel staat.
- Regenereer eerst het project: stap 8 bumpt `MARKETING_VERSION` in `project.yml`, en zonder
  `xcodegen generate` bouw je een `.xcodeproj` met het oude versienummer.
- Sluit het toestel met een kabel aan en ontgrendel het vóór de build. Wordt het alleen over
  het netwerk gezocht, dan loopt de build vast in *"Timed out waiting for all destinations…"*.

### Via Xcode (aanbevolen)
Toestelherkenning, koppeling en signing zijn precies waar de terminalroute struikelt; Xcode
doet dat zelf en meldt in gewone taal wat er mankeert. Ook de iCloud-valkuil hieronder zit er
al in: Xcode bouwt standaard naar `~/Library/Developer/Xcode/DerivedData`, buiten de projectmap.

1. `xcodegen generate` in de terminal.
2. `FableFlux.xcodeproj` openen; iPhone aangesloten en ontgrendeld.
3. **Product → Scheme → Edit Scheme → Run → Build Configuration: `Release`.** Sla je dit over,
   dan installeer je een Debug-build.
4. Het toestel kiezen in de toolbar en `⌘R`. Daarna de debugger stoppen met `⌘.`; de app blijft
   geïnstalleerd.
5. Controleren dat het verwachte versienummer op het toestel staat.

### Via de terminal (alternatief)
Bruikbaar als je het onbemand wilt draaien. Het blok zoekt het aangesloten toestel zelf op; typ
geen identifier over, want die verschilt per toestel. `xcrun devicectl list devices` toont per
toestel de hardware-UDID (`00008110-…`, gevolgd door `(UDID)`), en zowel `xcodebuild -destination
id=` als `devicectl` accepteren die. Filter niet op de kolom *State*: die wisselt tussen
`connected` en `available (paired)` (#148). Filter op *Reality* `physical`: de lijst bevat ook
simulators, die ook "iPhone" heten. Zonder aangesloten iPhone stopt het blok met een melding in
plaats van met een lege identifier.

```bash
xcodegen generate
DEVICE=$(xcrun devicectl list devices \
  | awk '/ physical *$/ && /iPhone/ { for (i = 1; i < NF; i++) if ($(i + 1) == "(UDID)") print $i }' \
  | head -1)
DERIVED=~/Library/Developer/Xcode/DerivedData/FableFlux-device
: "${DEVICE:?Geen aangesloten iPhone gevonden: sluit hem aan met een kabel en ontgrendel hem}" \
  && xcodebuild -project FableFlux.xcodeproj -scheme FableFlux -configuration Release \
    -destination "id=$DEVICE" \
    -derivedDataPath "$DERIVED" -allowProvisioningUpdates build \
  && xcrun devicectl device install app --device "$DEVICE" \
    "$DERIVED/Build/Products/Release-iphoneos/FableFlux.app"
```

De stappen hangen met `&&` aan elkaar. Zonder toestel start de build niet. Faalt de build, dan
installeert het blok niet de vorige app die nog in `$DERIVED` staat. Dat geldt ook als je het
blok in de terminal plakt: een losse regel zou daar gewoon doorlopen.

Staan er meerdere iPhones aangesloten, dan kiest het blok de eerste; `xcrun devicectl list devices`
toont welke dat is.

Controleer na afloop het versienummer:

```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "$DERIVED/Build/Products/Release-iphoneos/FableFlux.app/Info.plist"
```

### Bouw niet binnen de projectmap
Die staat in iCloud Drive, dat extended attributes op de buildoutput zet (waargenomen:
`com.apple.provenance`; ook `com.apple.FinderInfo` komt voor). `codesign` faalt dan met
*"resource fork, Finder information, or similar detritus not allowed"*. `xattr -rc` lost dit
niet op — die attributen komen terug of zijn niet te verwijderen; bouw naar een pad buiten de
projectmap. Xcode doet dat standaard al. Simulatorbuilds hebben hier geen last van omdat die
niet worden ondertekend.

## 10. Continuous integration (GitHub Actions)

Naast de handmatige stappen hierboven draait er een CI-workflow op elke pull request naar
`main`. Die doet precies drie dingen:

- **Opmaak** — draait swift-format over `FableFlux/` en `FableFluxTests/` en faalt als dat
  een diff oplevert.
- **Build-check** — dezelfde controle als stap 2, met `generic/platform=iOS Simulator`.
- **Tests** — de unit-tests in `FableFluxTests` op een simulator die de workflow zelf opzoekt.

Dat is bewust smal gehouden: het valideert wat een agent of reviewer anders handmatig moet
draaien, en niets meer.

### Wanneer draait de CI?
- Automatisch bij elke pull request naar `main`.
- Handmatig via GitHub → Actions → *CI* → *Run workflow*.

Niet bij een push naar `main`: dat verdubbelt het verbruik zonder dat het iets toevoegt aan
wat de PR-run al heeft gecontroleerd.

### Verhouding tot deze workflow
CI **vervangt stap 2 niet**. Draai de build-check lokaal vóór het committen; CI is het
vangnet dat betrapt wat er op een andere machine misgaat, niet de eerste keer dat je hoort
dat de build faalt. Stap 6 (review) blijft mensenwerk — CI toetst geen correctheid.

### Wat er bewust níét in zit
- **Release-/device-builds.** Signing werkt niet op een runner: `DEVELOPMENT_TEAM` staat vast
  in `project.yml` en er is geen certificaat. Met signing uitgeschakeld valideer je niets
  extra's. De distributie loopt via stap 9, op het toestel zelf.
- **SwiftLint.** Dit project gebruikt swift-format en heeft geen `.swiftlint.yml`; een
  strict-run op de standaardregels zou permanent rood staan.
- **`swift format lint`.** De opmaakstap toetst of de broncode door de formatter is gehaald,
  niet of hij aan alle lint-regels voldoet. Dat verschil is bewust: 27 regels zijn langer dan
  de ingestelde 120 tekens en allemaal string-literals — de CSS-blokken in `ItemDetailView`,
  de promptteksten in `AppConfiguration`, uitlegteksten in de instellingen. De formatter kan
  een literal niet afbreken (`reflowMultilineStringLiterals` staat op `never`), dus een
  lint-run zou daar permanent rood op staan zonder dat er iets aan te doen valt.
- **Code coverage / Codecov.** `xcodebuild` levert een `.xcresult`, geen `.lcov`, en er is
  geen Codecov-token. Toe te voegen zodra er iets met die cijfers gedaan wordt.

### Kosten
De repository is privé, dus macOS-minuten tellen **10×** tegen het inbegrepen quotum. Op het
Free-plan (2000 minuten/maand) is dat ruwweg 200 macOS-minuten, en een run kost al gauw 6–10
minuten — orde van grootte 20–30 runs per maand. Daarom: alleen op PR's, en
`cancel-in-progress` zodat een nieuwe push de vorige run afbreekt.

### Het gegenereerde project blijft actueel
`FableFlux.xcodeproj` wordt uit `project.yml` gegenereerd, maar staat ook in Git. CI draait
daarom `xcodegen generate` en faalt als dat een verschil oplevert. Voeg je een bestand toe,
draai dan `xcodegen generate` en neem het resultaat mee in dezelfde commit.

Waarom dit een controle verdient: zonder regeneratie mist je lokale Xcode-project bestanden
die CI wél bouwt. Een test kan dan in Xcode onzichtbaar zijn terwijl CI hem gewoon draait —
⌘U geeft dan groen over een halve suite. Zie #92 voor de afweging of deze bestanden
überhaupt in Git horen.

### Automatische review
`.github/workflows/claude-code-review.yml` draait de `/code-review`-plugin op een nieuwe PR
(`opened`) en zodra een concept-PR klaar is (`ready_for_review`). **Niet** bij elke push:
`synchronize` zou per commit een nieuwe review starten met grotendeels dezelfde bevindingen.
Een herhaalde review vraag je aan via Actions → *Claude Code Review* → *Run workflow*, met
het PR-nummer als invoer.

Dit vervangt stap 6 niet, het maakt die alleen moeilijker over te slaan. De review leest de
diff en draait niets: de build-check en de tests hierboven zijn wat daadwerkelijk aantoont
dat code compileert en werkt.

Vereist het repository secret `CLAUDE_CODE_OAUTH_TOKEN`; zonder dat secret faalt de job.
Draait op `ubuntu-latest`, dus zonder de 10×-vermenigvuldiging van de macOS-runs.

### @claude in issues en PR's
`.github/workflows/claude.yml` reageert wanneer je `@claude` noemt in een issue, een reactie
op een PR of een review. De opdracht is je eigen tekst; er is geen vaste prompt. Hij mag de
CI-resultaten van een PR lezen, dus vragen als "waarom staat de build rood?" werken.

De job heeft bewust alleen leesrechten: hij analyseert en antwoordt, maar pusht niets. Wil je
dat hij wel commits maakt, dan moet `contents` naar `write` — een bewuste keuze, want dan mag
een workflow die op een reactie afgaat de repository schrijven.

Gebruikt hetzelfde secret als de review hierboven.

### De workflow-bestanden
- **Locatie:** `.github/workflows/ci.yml` (build + tests) en
  `.github/workflows/claude-code-review.yml` (review)
- **Job:** `build-test`
- De Xcode-versie is gepind op `latest-stable`. De runner-standaard verschuift; zonder pin
  wisselt de SDK waartegen gebouwd wordt stilzwijgend mee.
- Het toestel voor de testrun wordt opgezocht via `xcrun simctl`, niet vastgelegd. Zie de
  waarschuwing bij stap 2: een vaste toestel/OS-combinatie breekt zodra die combinatie niet
  bestaat.
