# Code Review — RSSReader
**Datum:** 2026-05-29  
**Scope:** Volledige codebase (alle Swift-bronbestanden)  
**Methode:** Multi-angle statische analyse (7 perspectieven, verificatiefase)

---

## Bevindingen

### 1. OPMLParser — mapfolders worden afgebroken na de eerste feed `[CRITICAL]`
**Bestand:** `FableFlux/Services/OPMLParser.swift:63`

`didEndElement` wordt aangeroepen voor élk `<outline>`-element — zowel mapelementen als feedelementen. Alleen mapelementen verhogen `depth`, maar alle elementen verlagen het. Hierdoor wordt `currentFolderName` al genulld bij het sluiten van de eerste feed in een map.

**Scenario:** Een OPML-bestand met `<outline text="Tech"><outline xmlUrl="f1"/><outline xmlUrl="f2"/></outline>`:
- f1 krijgt `folderName = "Tech"` ✓
- Sluitingstag van f1 → `depth` wordt 0 → `currentFolderName = nil`
- f2 wordt geïmporteerd met `folderName = nil` en verschijnt in "Overig" ✗

Elke OPML-map met meer dan één feed is hierdoor stil gebroken.

**Fix:** Gebruik een aparte teller (`folderDepth`) die alleen wordt verhoogd/verlaagd voor mapelementen, niet voor feedelementen.

---

### 2. TopicClusteringService — Claude API-fouten worden stil genegeerd `[HIGH]`
**Bestand:** `FableFlux/Services/TopicClusteringService.swift:209`

De HTTP-statuscode van de Claude API-response wordt niet gecontroleerd. Een 401 (ongeldige API-sleutel) of 429 (limiet bereikt) retourneert een Anthropic-foutbody die niet past in de `Res`-struct, waardoor `JSONDecoder` een fout gooit — en de functie stilletjes terugvalt op `localSummary`.

**Scenario:** Gebruiker vult een ongeldige API-sleutel in. Elke summary-aanvraag krijgt HTTP 401 terug, decoding mislukt, de catch-block logt de fout alleen in OSLog en retourneert een lokale samenvatting. De UI ziet er identiek uit aan de situatie zonder API-sleutel — geen foutmelding.

**Fix:** Controleer de statuscode na de netwerkaanroep (vergelijk `checkHTTP` in `MastodonService`).

---

### 3. MastodonService — Image-URLs niet ge-escaped in HTML-attribuut `[MEDIUM]`
**Bestand:** `FableFlux/Services/MastodonService.swift:273`

Image-URLs uit de Mastodon API worden direct in een `src`-attribuut geïnterpoleerd zonder HTML-attribuut-escaping:

```swift
"<img src=\"\(img.url)\" alt=\"\" style=\"...\">"
```

Een URL met een letterlijk `"` sluit het attribuut vroegtijdig, produceert misvormde HTML en wordt permanent opgeslagen in SwiftData.

**Fix:** Vervang `"` door `&quot;` in de URL voor interpolatie (of gebruik `String(format:)` met `addingPercentEncoding`).

---

### 4. MastodonService — MIME-type hardcoded als `image/jpeg` `[MEDIUM]`
**Bestand:** `FableFlux/Services/MastodonService.swift:267`

```swift
item.enclosureMIMEType = "image/jpeg"  // altijd, ongeacht het werkelijke formaat
```

Mastodon-bijlagen kunnen PNG, GIF, WebP of AVIF zijn. Het verkeerde MIME-type wordt permanent opgeslagen in SwiftData.

**Fix:** Leid het subtype af uit de URL-extensie of laat `enclosureMIMEType` op `nil` staan voor Mastodon-afbeeldingen.

---

### 5. ItemDetailView — `enclosureURL` niet ge-escaped in HTML `[MEDIUM]`
**Bestand:** `FableFlux/Views/ItemDetailView.swift:225`

```swift
rssHTML += "\n<img src=\"\(imgURL)\" alt=\"\" style=\"...\">"
```

Dezelfde escaping-omissie als bevinding #3, maar dan voor `item.enclosureURL` in de detailweergave. JavaScript is uitgeschakeld in de WKWebView dus er is geen XSS-risico, maar het afbeelding laadt niet en de HTML in `displayHTML` is misvormd.

**Fix:** Escape `"` → `&quot;` in `imgURL` voor interpolatie.

---

### 6. FeedRefreshService — Alleen de laatste Mastodon-fout wordt getoond `[LOW]`
**Bestand:** `FableFlux/Services/FeedRefreshService.swift:61`

In de Mastodon-vernieuwingsloop wordt `lastError` bij elke account overschreven:

```swift
for account in accounts {
    // ...
    lastError = e.errorDescription  // overschrijft vorige fout
}
```

Als meerdere accounts mislukken, verdwijnt elke fout behalve de laatste stilletjes.

**Fix:** Voeg fouten samen (bijv. kommagescheiden) of gebruik een `[String]` array.

---

### 7. MastodonService — Pruning-logica gedupliceerd `[LOW]`
**Bestand:** `FableFlux/Services/MastodonService.swift:344`

De bewaarperiode-logica (lees UserDefaults, bereken cutoff, verwijder niet-opgeslagen items) is identiek geïmplementeerd in zowel `FeedRefreshService.pruneOldItems` als `MastodonService.refreshFeed`. Een toekomstige wijziging in één kopie zal de andere missen.

**Fix:** Verplaats de pruning-logica naar `FeedRefreshService.pruneOldItems` en roep die methode aan vanuit `MastodonService`.

---

## Overzicht

| # | Bestand | Ernst | Samenvatting |
|---|---------|-------|--------------|
| 1 | `OPMLParser.swift:63` | Kritiek | Alle feeds na de eerste in een OPML-map krijgen geen mapnaam |
| 2 | `TopicClusteringService.swift:209` | Hoog | Claude API-fouten (401/429) worden stil genegeerd |
| 3 | `MastodonService.swift:273` | Gemiddeld | Image-URLs niet ge-escaped → corrupte HTML in SwiftData |
| 4 | `MastodonService.swift:267` | Gemiddeld | `enclosureMIMEType` altijd `image/jpeg`, ongeacht werkelijk formaat |
| 5 | `ItemDetailView.swift:225` | Gemiddeld | `enclosureURL` niet ge-escaped in HTML-attribuut |
| 6 | `FeedRefreshService.swift:61` | Laag | Alleen laatste Mastodon-fout zichtbaar bij meerdere accounts |
| 7 | `MastodonService.swift:344` | Laag | Pruning-logica gedupliceerd, divergentierisico bij toekomstige wijzigingen |
