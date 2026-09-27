# FableFlux

Een native iOS RSS-lezer met AI-gedreven samenvattingen, Mastodon-integratie en ondersteuning voor podcasts en video's.

## Doel

FableFlux brengt al je informatiebronnen samen in één app: RSS-feeds, Mastodon-tijdlijnen, podcasts en videokanalen. De app groepeert artikelen automatisch per onderwerp en genereert samenvattingen — lokaal of via de Claude API — zodat je snel het nieuws kunt overzien zonder alles te hoeven lezen.

---

## Functionaliteiten

### Feeds & organisatie
- **RSS/Atom-feeds** toevoegen via URL of OPML-import
- **Mappen** om feeds te groeperen (automatisch of handmatig)
- Automatische detectie van video- en audiofeeds (YouTube, Vimeo, podcasts)
- Swipe-acties: artikelen bewaren of feeds vernieuwen

### Lezen
- Ingebouwde reader met opmaak, donkere modus en instelbare lettergrootte
- Automatische artikel-extractie voor de volledige tekst
- Alle links openen in de in-app browser (SFSafariViewController)
- Miniatuurafbeeldingen in de artikellijst

### AI-samenvattingen
- Artikelen worden automatisch geclusterd per onderwerp (AI, Tech, Politiek, Sport, enz.)
- Samenvattingen worden gegenereerd via de **Claude API** (Haiku) of lokaal als fallback
- Keuze tussen **Nederlands** en **Engels**
- Eigen onderwerpen aanmaken met aangepaste trefwoorden

### Mastodon
- Verbinden met elk Mastodon-instantie via OAuth
- Tijdlijn verschijnt als gewone feed, inclusief boosts en afbeeldingen
- Content warnings (CW) weergegeven als uitklapbare sectie

### Media
- **Podcasts**: inline audiospeler met voortgangsbalk en tijd-weergave
- **YouTube / Vimeo**: afspeelknop opent video in in-app browser
- **Directe video's** (MP4): native AVPlayer

### Instellingen
| Instelling | Beschrijving |
|---|---|
| Claude API-sleutel | Inschakelen van AI-samenvattingen (opgeslagen in Keychain) |
| Taal samenvattingen | Nederlands of English |
| Verberg gelezen artikelen | Filtert de artikellijst |
| Teller per feed | Totaal of alleen ongelezen |
| Regels voorvertoning | 1–5 regels beschrijving in de lijst |
| Miniatuurafbeeldingen | Aan/uit |
| Lettergrootte | Slider 13–23 pt, schaalt mee met Dynamic Type |
| Bewaarperiode | Hoe lang artikelen bewaard blijven |

---

## Technische opbouw

### Vereisten
- iOS 17+
- Xcode 15+
- Swift 5.9+

### Architectuur
```
FableFlux/
├── Models/          # SwiftData-modellen (Feed, FeedItem, MastodonAccount, Topic…)
├── Views/           # SwiftUI-views per scherm
├── Services/        # Businesslogica (parsing, refresh, clustering, Keychain)
└── AppConfiguration.swift  # Centrale constanten en sleutels
```

- **SwiftData** voor lokale opslag van feeds, artikelen en instellingen
- **Swift Concurrency** (`async/await`, `@Observable`) voor alle asynchrone bewerkingen
- **KeychainService** voor veilige opslag van tokens en API-sleutels
- **WKWebView** met aangepast HTML-template voor de reader
- **NaturalLanguage** framework voor lokale trefwoordextractie

### Externe afhankelijkheden
Geen. De app gebruikt uitsluitend Apple-frameworks en de Anthropic REST API.

### Claude API (optioneel)
Zonder API-sleutel werkt de app volledig — samenvattingen worden dan lokaal gegenereerd op basis van de artikelteksten. Met een sleutel worden samenvattingen gegenereerd via `claude-haiku-4-5`.

Een sleutel is aan te maken op [console.anthropic.com](https://console.anthropic.com).

---

## Installatie

1. Clone de repository
2. Open `FableFlux.xcodeproj` in Xcode
3. Selecteer een simulator of fysiek apparaat
4. Build en run (`⌘R`)

> Een Claude API-sleutel is niet verplicht. Alle basisfuncties werken zonder.

---

## Licentie

Privé project. Alle rechten voorbehouden.
