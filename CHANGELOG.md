# Changelog

Alle noemenswaardige wijzigingen aan dit project worden in dit bestand bijgehouden.

Het formaat is gebaseerd op [Keep a Changelog](https://keepachangelog.com/nl/1.1.0/)
en dit project volgt [Semantic Versioning](https://semver.org/lang/nl/).

## [Unreleased]

### Gewijzigd
- Een mislukte SwiftData-opslag verdwijnt niet langer stil: alle 28 opslagplekken lopen via één helper die de fout logt, en bij een expliciete actie (bewaren, verwijderen, mappen, onderwerpen, feedinstellingen, OPML-import) toont het scherm een melding (#123)
- De artikelenlijst bouwt niet langer bij elke view-update een array over de hele geladen lijst, en bouwt de bestemming van een rij pas op wanneer je erop tikt in plaats van vooraf (#115)
- De aanroep van de Anthropic API staat nu in een eigen `AnthropicClient`; `TopicClusteringService` houdt clustering en samenvattingsbeleid, inclusief de terugval op de lokale samenvatting. Gedrag ongewijzigd (#125)
- Verversen haalt de bestaande artikelen van een feed niet langer één voor één uit de database: dubbelcontrole, datumherstel en opruimen gebruiken elk één gebundelde query. In een meting met 300 artikelen daalt het aantal leesqueries van 301 naar 13 (#119)
- De samenvatting haalt alleen de artikelen binnen het 48-uursvenster van meetellende feeds op, in één query, in plaats van eerst alle artikelen afzonderlijk te laden. In een meting met 600 artikelen daalt het aantal leesqueries van 402 naar 3 (#120)
- De teller per feed in de feedlijst wordt geteld met één `COUNT`-query per feed in plaats van alle artikelen van elke feed te laden, en alleen bijgewerkt zolang de lijst in beeld is. In de stand "ongelezen" laadde elke teller eerst elk artikel afzonderlijk (#121)

### Opgelost
- De bewaarknop in het artikelscherm verdween mee zodra een artikel geen link had (bijvoorbeeld een Mastodon-bericht zonder externe verwijzing), terwijl bewaren geen URL nodig heeft; alleen "open in browser" en "delen" blijven nu achter de link hangen (#118)
- De Claude-sleutel kan niet meer verloren gaan bij een mislukte Keychain-write: de Keychain werkt een bestaande waarde bij in plaats van die eerst te verwijderen, de oude kopie in de instellingen verdwijnt pas na een geslaagde write, en een nog niet verhuisde sleutel wordt bij het opstarten eenmalig naar de Keychain gemigreerd (#124)
- Hetzelfde artikel kwam meermaals binnen in één feed wanneer de feed het met een wisselend fragment in de guid publiceert (BBC: `…#1`, `…#9`). De dubbelcontrole vergelijkt de guid nu zonder dat fragment, ook binnen één verversing (#135)

## [1.9.0] - 2026-09-16

### Gewijzigd
- De artikelenlijst haalt artikelen per 50 op en laadt bij tijdens het scrollen, in plaats van de hele bewaarperiode in één keer (#106)

### Opgelost
- Tijdens het vegen tussen artikelen was even een wit vlak zichtbaar: een webview zonder geladen document tekent zichzelf wit, en sinds de prestatiewijziging laadt een buurpagina zijn HTML pas als je er bent. De webview begint nu met een leeg document in de app-achtergrond (#106)
- Onderwerpenbeheer (`TopicsManagementView`, `TopicEditView`) was nog volledig Engels; alle zichtbare tekst is nu Nederlands, met "favoriet" als consistente term voor `isLiked` (#61)

## [1.8.1] - 2026-09-15

### Gewijzigd
- De artikelenlijst haalt `feed` en `factCheckResults` vooruit op in plaats van per rij afzonderlijk; dat scheelt een databaseleesactie per relatie per zichtbare rij (#106)
- Het artikelenscherm filtert nu in de database in plaats van in het geheugen. Het haalde eerder elk artikel op en filterde daarna per artikel over `feed.folder`, wat duizenden losse database-acties op de main thread opleverde (#108)
- Artikel-extractie en fact-check draaien alleen nog voor het artikel dat je bekijkt, niet voor de buurpagina's van de pagina-TabView; een artikel geldt ook pas als gelezen zodra het de zichtbare pagina is (#106)
- Stap 8 en 9 van `Workflow-feature.md`: taggen pas na het mergen van de release-PR, en het onderscheid tussen het `devicectl`-id en de hardware-UDID die `xcodebuild` wil
- Stap 9 van `Workflow-feature.md` beschrijft Xcode als aanbevolen route voor het installeren op het toestel; de terminalroute staat er als alternatief onder

### Opgelost
- Een artikel met een publicatiedatum eeuwen in de toekomst bleef na elke verversing terugkomen: het sorteerde bovenaan, viel binnen elk samenvattingsvenster en werd door de bewaarperiode nooit opgeruimd. De parser weigert nu een datum die meer dan een etmaal vóórloopt, en bestaande rijen worden bij de eerstvolgende verversing gecorrigeerd (#103)

## [1.8.0] - 2026-09-14

### Toegevoegd
- CI controleert of de broncode met swift-format is opgemaakt en faalt als dat niet zo is
- CI faalt als het getrackte `RSSReader.xcodeproj` afwijkt van wat `project.yml` oplevert, zodat een vergeten `xcodegen generate` zichtbaar wordt in plaats van stil (#92)

### Verwijderd
- Vier verouderde documentatiebestanden uit `RSSReader/Views/` (`CODE_IMPROVEMENTS.md`, `PRE_FLIGHT_CHECKLIST.md`, `QUICK_FIX.md`, `TEST_INSTRUCTIONS.md`) — instructies uit juni die de huidige workflow tegenspraken (#64)
- De dode kopie `RSSReader.xcodeproj/AppConfiguration.swift` en de gebruikersspecifieke `xcuserdata/`, die nu ook in `.gitignore` staat (#53)

### Gewijzigd
- De samenvatting op Vandaag kijkt 48 uur terug in plaats van de volle bewaarperiode van 30 dagen. De lege staat legt dat venster uit; de artikelen zelf blijven zichtbaar in Artikelen en Bewaard (#89)

### Opgelost
- De knoppen rechtsboven in het artikelscherm (bewaren, open in browser, delen) stonden dubbel: de pagina-TabView houdt de buurpagina in leven en die leverde zijn toolbar aan dezelfde navigatiebalk (#98)
- Een artikelkaart met een brede bannerafbeelding liep buiten het scherm, waardoor de tekst aan beide zijden werd afgekapt: de afbeelding bepaalde de breedte van de kaart in plaats van andersom (#96)
- Bij het bladeren door artikelen flitste er wit tussen twee pagina's: de pagina-TabView en het artikelscherm hadden geen eigen achtergrond, waardoor de systeemstandaard (wit) zichtbaar werd in plaats van `Theme.background`
- Artikelen zonder publicatiedatum werden nooit opgeruimd: de bewaarperiode behandelde een ontbrekende datum als oneindig ver in de toekomst. Ze krijgen nu een ophaalmoment (`fetchedAt`) en verouderen daarmee gewoon (#89)

## [1.7.1] - 2026-09-13

### Toegevoegd
- Automatische code-review op een nieuwe pull request via GitHub Actions (vereist het repository secret `CLAUDE_CODE_OAUTH_TOKEN`)
- `@claude` noemen in een issue, PR-reactie of review start een Claude-run die antwoordt in dezelfde draad (alleen leesrechten; pusht niets)
- R12 vastgelegd in de projectbrief: per feed instellen of die meetelt in de AI-samenvatting
- Unit-tests voor `RSSParser`: velden, datumformaten, mediatype, afbeeldingen en randgevallen
- CI op GitHub Actions: elke pull request naar `main` draait de build-check en de unit-tests op een iOS-simulator
- Unit-tests voor `OPMLParser` die de mapindeling van geïmporteerde feeds vastleggen

### Opgelost
- De samenvatting op Vandaag werd gebaseerd op de eerst opgeslagen artikelen in plaats van de nieuwste. Bij een onderwerp met meer dan tien artikelen vielen nieuwe artikelen structureel buiten de samenvatting, waardoor die niet meer veranderde (#65)
- De terugval op de eerste `<img>` in de beschrijving kwam nooit in de feed terecht: de afbeelding werd gezet op het item terwijl een eerder gemaakte kopie werd opgeslagen. Artikelen zonder expliciete afbeelding hadden daardoor altijd een lege thumbnail
- OPML-import verloor de mapindeling van elke feed na de eerste in een map; die feeds belandden in "Overig" (#78, #66)
- Mastodon-afbeeldingen kregen altijd het MIME-type `image/jpeg`, ongeacht het werkelijke formaat (#81)
- Afbeeldings-URL's werden niet ge-escaped voordat ze in HTML-attributen kwamen, waardoor een URL met een aanhalingsteken de HTML brak (#80, #82)
- Bij meerdere Mastodon-accounts bleef alleen de laatste fout zichtbaar; alle fouten worden nu getoond (#83)

### Gewijzigd
- De bewaarperiode-logica staat nog maar op één plek: `MastodonService` roept `FeedRefreshService.pruneOldItems` aan (#84)

## [1.7.0] - 2026-09-10

### Toegevoegd
- Per feed instelbaar of die meetelt in de AI-samenvatting op Vandaag ("Meenemen in samenvatting" in de feedinstellingen, standaard aan). Een uitgesloten feed verdwijnt niet: de artikelen blijven gewoon zichtbaar in Artikelen en Bewaard. Bij het wijzigen draait de clustering direct opnieuw

### Opgelost
- Een clusteringronde die door een nieuwere wordt ingehaald, overschrijft het resultaat niet meer; de nieuwste ronde wint, omdat die de actuele feeds en instellingen kent
- Een afgebroken clusteringronde maakte de samenvatting op Vandaag leeg in plaats van het bestaande resultaat te laten staan

## [1.6.2] - 2026-09-10

### Gewijzigd
- De schermtitel staat nu vast compact in het midden van de navigatiebalk in plaats van eerst groot boven de lijst; de balk is daardoor smaller en de titel blijft altijd zichtbaar

### Opgelost
- De titel verdween op iOS 26 volledig zodra je in een lijst scrolde: het afgedwongen balkmateriaal (`.toolbarBackground(.ultraThinMaterial)`) onderdrukte de compacte titel. Dat materiaal is uit alle lijstschermen gehaald, zodat iOS zijn eigen scroll-edge-effect neerlegt
- De audiospeler werd op iOS 26 bovenaan afgesneden door de zwevende navigatiebalk. De spelers in de audio- en videolayout houden die balk nu vrij, en de artikeltekst eronder krijgt niet langer de bovenmarge die alleen bij de reader-layout hoort

## [1.6.1] - 2026-09-10

### Opgelost
- Artikeltekst liep op iOS 26 onder de zwevende navigatiebalk door: het bronlabel was half onleesbaar bij het openen van een artikel. De balk krijgt geen eigen materiaal meer opgelegd (iOS legt zelf een scroll-edge-effect neer), de webview is niet langer volledig doorzichtig zodat dat effect iets heeft om overheen te vervagen, en de eerste regel begint onder de balk

## [1.6.0] - 2026-09-10

### Toegevoegd
- Pull-to-refresh op het startscherm Vandaag: naar beneden trekken ververst alle feeds en draait de clustering opnieuw, ook binnen de debounce van twee minuten (bij automatisch verversen blijft die debounce gelden)

### Gewijzigd
- Een tweede refresh die start terwijl de eerste nog loopt, wacht die af in plaats van een tweede ronde te draaien; de aanroeper gaat pas verder als de data compleet is
- `clusteringDebounce` staat nu in `AppConfiguration` in plaats van los in `ContentView`
- `Versiebeheer.md` noemt bij de installatiestap nu dezelfde oorzaak als `CLAUDE.md` en `Workflow-feature.md`: iCloud Drive zet extended attributes op de buildoutput (waargenomen: `com.apple.provenance`) en `xattr -rc` lost dat niet op

## [1.5.0] - 2026-09-10

### Gewijzigd
- Artikelen opent nu direct op de artikelstroom met een blijvende filterbalk per map ("Alle" plus een chip per map, keuze blijft bewaard na herstart), zodat elk artikel met één tik bereikbaar is; feedbeheer verhuisde naar "Feeds beheren" in het toolbarmenu en de hardgecodeerde blauwtinten in de feedlijst zijn vervangen door themakleuren. Het tabblad heeft een eigen Vernieuwen-knop en pull-to-refresh, en toont een uitleg wanneer er niets te zien is (geen feeds, een filter zonder artikelen, of feeds die nog leeg zijn)
- Vandaag toont nu de samenvatting zelf als kaartenscherm per onderwerp — beweringen met klikbare bronchips, bronduiding en fact-checkwaarschuwing direct zichtbaar — in plaats van een inhoudsopgave die eerst naar de samenvatting doorlinkt; bij meer dan drie beweringen verschijnt een "Toon meer"-knop, en alle teksten zijn nu Nederlands
- Tabbalk teruggebracht van vijf naar drie tabbladen (Vandaag, Artikelen, Bewaard) met leesbaardere labels van 11pt: Onderwerpen staat nu in Instellingen en Instellingen opent via een tandwielknop in de toolbar van Vandaag, als sheet met een Gereed-knop om te sluiten
- Releaseworkflow beschrijft nu het installeren van de nieuwe versie op de iPhone als vaste stap, inclusief de eis om device-builds buiten de iCloud-map te bouwen (anders faalt `codesign`)
- `CLAUDE.md` waarschuwt nu bij de toolchain dat de buildoutput van een device-build buiten de projectmap moet vallen (anders faalt `codesign`), en `Workflow-feature.md` benoemt het waargenomen attribuut (`com.apple.provenance`) plus dat `xattr -rc` het probleem niet oplost

## [1.4.2] - 2026-08-09

### Opgelost
- `RSSReaderTests` staat nu als testtarget in `project.yml` en het gedeelde `RSSReader`-scheme voert de tests uit, zodat `xcodebuild test` en `⌘U` de bestaande unit-tests daadwerkelijk draaien en dit een `xcodegen generate` overleeft

## [1.4.1] - 2026-08-09

### Opgelost
- Clustering draait al het CPU-werk (HTML-strippen van artikelteksten, tokenisatie en trefwoord-matching) nu off-main via `Task.detached` in plaats van op de MainActor, zodat refresh en samenvatting de UI niet langer seconden blokkeren; resultaten blijven identiek. Het HTML-strippen is bovendien geëxtraheerd naar `FeedItem.plainText(from:)` met gecachte regexes (geen per-aanroep regex-compilatie)
- Artikellijst in de samenvattingsdetailpagina wordt lazy opgebouwd (`LazyVStack`), zodat het openen van een groot onderwerp (honderden artikelen) niet langer alle rijen en hun navigatiedoelen in één main-thread-pass bouwt en de UI blokkeert
- Clustering hergebruikt en vult nu de platte-tekst-cache van artikelen, zodat dezelfde HTML niet elke ronde opnieuw gestript wordt en de lijstweergaven het strippen niet alsnog op de MainActor doen; daarnaast stopt het off-main CPU-werk nu daadwerkelijk zodra de aanroeper wordt geannuleerd

## [1.4.0] - 2026-07-29

### Toegevoegd
- Unit-tests voor de clustering-toewijzing (woordgrens, meerwoord-frase, case-insensitiviteit, minimumdrempel en tie-break) door de matching-logica testbaar te isoleren zonder productiegedrag te wijzigen
- Bron-duidingsstrip in het artikeldetail: boven alle layouts (audio/video/reader) tonen de politieke positie (`BiasBarView`) en betrouwbaarheid (`ReliabilityBadgeView`) zodra de feed een beoordeling heeft; tik op de bias-balk opent de bestaande transparantie-sheet, en zonder beoordeling verschijnt er niets

### Gewijzigd
- Clustering hergebruikt nu één `NLTokenizer`-instantie in `wordBoundaryText` in plaats van er per aanroep een aan te maken; identieke uitvoer, minder allocaties in de hotloop

## [1.3.0] - 2026-07-29

### Toegevoegd
- Subtiele betrouwbaarheidsmarkering per bron in de samenvatting: de artikelrijen en bron-chips tonen nu een compacte betrouwbaarheidsbadge (hergebruik `ReliabilityBadgeView`), zodat low/mixed bronnen zichtbaar geduid worden; onbekende betrouwbaarheid toont niets en er wordt niets uit de samenvatting weggelaten
- Fact-check-waarschuwing per onderwerp op de samenvattingspagina (lijst en detail): toont een compacte, neutrale melding zodra minstens één artikel in het cluster een betwijfeld verdict heeft, met inklapbare details per bewering en beoordelaar; classificatie is deterministisch (geen AI-call)

### Gewijzigd
- Samenvattingsprompt stuurt bij een onderwerp met meerdere bronnen nu expliciet op synthese: de belangrijkste beweringen leiden met door twee of meer bronnen bevestigde ontwikkelingen, terwijl enkelvoudige-bron-items behouden blijven (R11-garantie ongewijzigd)

## [1.2.1] - 2026-07-29

### Gewijzigd
- App opent nu standaard op de samenvatting-tab in plaats van de feedlijst

## [1.2.0] - 2026-07-29

### Toegevoegd
- Per-onderwerp bronduiding op de samenvattingspagina (lijst en detail): een geaggregeerd politieke-kleurspectrum met "overwegend"-label plus een afgeleid betrouwbaarheidslabel over de distinct bronnen; onbekende ratings tellen niet mee en worden nooit geraden

### Gewijzigd
- Claude API-sleutel wordt in Settings nu echt gevalideerd (lichte `GET /v1/models`): de statusindicator toont pas groen "actief" na een geslaagde controle, met aparte standen voor valideren, ongeldige sleutel (401/403) en "kon niet valideren" bij netwerkfouten — in plaats van groen zodra het veld niet leeg is
- Topic-clustering matcht trefwoorden nu op woordgrens (hele woorden/frasen) in plaats van deelstring, met een instelbare minimumdrempel, zodat toevalstreffers als "ai" in "email" geen artikelen meer in het verkeerde onderwerp trekken
- Samenvattingsprompt stuurt nu op hybride bron-synthese: beweringen citeren alle onderbouwende artikelen bij overlappende berichtgeving, één bron bij een enkele bron (R11-garantie behouden)
- Bron-chip onder een bewering toont nu de artikeltitel (met feednaam als secundair label), zodat meerdere bronnen uit dezelfde feed onderscheidbaar zijn

## [1.1.0] - 2026-07-24

### Gewijzigd
- Instellingenpagina heringedeeld in zeven logische secties, volledig Nederlandstalig
- Alle drie de tekstgrootte-instellingen gebruiken nu dezelfde slider in procenten (80–150%), met één herstel-knop

### Toegevoegd
- Borging bron-attributie (R11): beweringen zonder bron-id zijn onconstrueerbaar en een validatiegate faalt zichtbaar bij een regressie
- Inline bronverwijzingen in samenvattingen: beweringen met stabiele bron-ids, aantikbaar naar het bronartikel in de detailweergave
- Versiebeheer-workflow (Workflow-feature.md) en dit changelog-bestand
- Instelbare tekstgrootte voor bronanalyse en fact-check (10–18pt) in Settings
- Bronanalyse op artikelkaarten: bias-balk, betrouwbaarheidsbadge en fact-check-chip
- Gebeurtenisgroepering in de mapweergave
- Retro Future UI-herontwerp: warme kleuren, magazine-cards, zwevende tab bar, leesvoortgangsbalk

## [1.0.0] - 2026-06-01

### Toegevoegd
- Eerste versie: RSS/Atom-feeds, mappen, OPML-import, Mastodon-integratie,
  AI-samenvattingen (Claude API), podcast- en videoweergave, bewaarde artikelen
