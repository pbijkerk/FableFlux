# Onderzoek: AI-samenvatting via de Ubuntu-hub (#237)

**Datum:** 2026-11-23
**Doel uit de projectbrief:** een uitgebreidere, betrouwbaardere samenvatting per onderwerp als hoofdpagina (R1–R3, R11), terwijl de feeds bruikbaar blijven zonder AI (R8).
**Voedt de beslissing:** hoe de hub-service wordt bereikt, beveiligd en aangesproken, vóórdat er een bouw-taakkaart komt (besluit Optie B, 2026-11-19).

## 1. Wat er nu in de app zit

- Eén aanroeppunt: `TopicClusteringService.generateSummaryWithClaude` (`FableFlux/Services/TopicClusteringService.swift:655`) roept `AnthropicClient.generateSummary` aan en valt bij `nil` terug op `localSummary` (`:626`). Die terugval is de R8-borging en blijft bruikbaar voor de hub.
- `AnthropicClient` (`FableFlux/Services/AnthropicClient.swift`) is alleen transport en formaat. Prompt en parser zijn los van Anthropic:
  - invoer: onderwerp, maximaal `maxArticlesPerSummary` = 10 artikelen (`AppConfiguration.swift:100`) met titel + 300 tekens beschrijving, lengte (`maxTokens` 300/600/1000, `AppConfiguration.swift:217`) en taal;
  - uitvoer: `{"statements":[{"text":"…","sources":[1,2]}]}`; `parseStatements` mapt de bronnummers naar `FeedItem.id` en gooit bronloze beweringen weg (R11).
- Fact-check gebruikt de Google Fact Check API, niet Claude (`FactCheckService.swift:25-32`). Die verhuist dus niet mee.
- De `URLRequest` heeft geen eigen `timeoutInterval`, dus de standaard van 60 s geldt. Voor een hub die soms onbereikbaar is, is dat te lang voor de terugval.

**Gevolg:** de verhuizing past achter één naad. Er komt een tweede client naast `AnthropicClient`, met hetzelfde invoer- en uitvoercontract. Bronduiding, fact-check, inline bronverwijzingen en UI blijven ongewijzigd.

## 2. Bereik vanaf 4G (Tailscale)

- De iPhone draait de Tailscale-app als VPN; de Ubuntu-machine komt in hetzelfde tailnet. Van buitenaf gaat het verkeer direct of via Tailscale-relays (DERP), zonder poort open te zetten in de thuisrouter. *Niet getest vanaf 4G*: dat is een check van één minuut op het toestel zelf (mens-taak, zie §6).
- **HTTPS zonder eigen certificaat:** `tailscale serve` levert een geldig certificaat voor `<machine>.<tailnet>.ts.net`, mits HTTPS in de tailnet-DNS-instellingen aan staat ([Tailscale Serve](https://tailscale.com/kb/1312/serve)). Zo blijft het een gewone `https://`-URL, in lijn met `IOS_Swift.md`.
- **Knelpunt — geen sudo op het `hermes`-account.** De standaardinstallatie van `tailscaled` en `tailscale serve` vraagt root. Er zijn twee uitwegen:
  1. **Eenmalig sudo** door de eigenaar van de machine: Tailscale installeren en `tailscale serve --bg https / http://127.0.0.1:<poort>` instellen. De service zelf draait daarna gewoon onder `hermes`. *Mijn advies*: standaard, eenvoudig te onderhouden, en de identiteitsheaders (§4) werken.
  2. **Zonder root:** de service als Go-programma met de `tsnet`-bibliotheek. Die draait een eigen Tailscale-node in het proces, haalt zelf een certificaat op en heeft geen root nodig ([tsnet](https://tailscale.com/docs/reference/tsnet-server-api.md)). Nadeel: de taal ligt dan vast op Go, en het Tailscale-stuk moet je zelf onderhouden.
  - Of `tailscale serve`/`cert` werkt met een `tailscaled` in userspace-modus onder een gewone gebruiker, kon ik niet bevestigen in de documentatie. Dat is geen route om op te plannen.

## 3. Endpoint-vorm (contract app ↔ hub)

Voorstel: neem het bestaande contract één op één over, zodat `parseStatements` en de R11-gate ongewijzigd blijven.

```http
POST https://<hub>.ts.net/v1/summarize
Authorization: Bearer <token>
Content-Type: application/json

{"topic":"…","language":"nl","length":"normaal",
 "articles":[{"n":1,"title":"…","description":"…"}]}

200 → {"statements":[{"text":"…","sources":[1,2]}]}
```

- **De prompt verhuist naar de hub.** Dan kan hij daar zwaarder en langer worden zonder app-release; dat is de kern van het besluit. De app stuurt alleen gegevens.
- **Structured output aan de serverkant:** Ollama dwingt een JSON-schema af via het `format`-veld van `/api/chat` ([Ollama structured outputs](https://docs.ollama.com/capabilities/structured-outputs)). Dat maakt het "geen JSON terug"-risico van een 8B-model veel kleiner. De hub valideert ook zelf dat elk bronnummer bestaat, net als de app.
- **Foutgedrag:** elke niet-2xx, elke time-out en elk onparseerbaar antwoord geeft in de app `nil`, en dus `localSummary` (R8). De time-out moet kort zijn (in de orde van 20–30 s per onderwerp; vast te stellen na meting) en komt in `AppConfiguration`.
- **Versie in het pad** (`/v1/`), zodat app en hub los van elkaar kunnen wijzigen.

## 4. Authenticatie

Twee lagen, allebei goedkoop:

1. **Netwerk:** alleen apparaten in het tailnet bereiken de hub. De service luistert alleen op `127.0.0.1`; `tailscale serve` zet hem door. Tailscale raadt dat zelf aan, omdat anders iemand de identiteitsheaders kan vervalsen ([Serve-headers](https://tailscale.com/s/serve-headers)).
2. **Applicatie:** een gedeeld bearer-token. In de app staat het in de Keychain via `KeychainService`, net als nu de Claude-sleutel. Op de hub staat het in een bestand met rechten 600. Dit beschermt ook tegen andere apparaten in hetzelfde tailnet.

Optioneel daarbovenop: de hub controleert de header `Tailscale-User-Login`, die `tailscale serve` zelf zet en bij inkomende verzoeken eerst wegpoetst. Dat werkt alleen met route 1 uit §2, en alleen voor gebruikersapparaten, niet voor getagde apparaten.

## 5. Risico dat de beslissing raakt: kwaliteit van `llama3.1:8b`

Het besluit noemt `llama3.1:8b` als model. De brief eist een samenvatting die *uitgebreider én betrouwbaarder* is dan de huidige Haiku-versie, en waarin elke bewering naar een bron herleidbaar is (R11). Of een 8B-model dat haalt, met name de juiste bronnummers bij synthese over meerdere artikelen, is **niet gemeten**. De eerder geteste NL-kwaliteit gaat over taal, niet over brontrouw. Ook de snelheid op deze hardware (±10 onderwerpen per verversing) is onbekend.

Dit onderzoek legt daarom een keuze voor (zie het issue): meet eerst met een vergelijking op dezelfde invoer, of houd Claude als terugval aan de serverkant.

## 6. Voorgestelde volgorde na de beslissing

1. **Mens:** Tailscale op de iPhone en de Ubuntu-machine (route 1 vraagt eenmalig sudo), HTTPS in het tailnet aanzetten, en vanaf 4G `https://<hub>.ts.net` openen in Safari.
2. **Agent:** de hub-service (endpoint uit §3, prompt verhuisd, Ollama met `format`-schema, token-check), plus een vergelijkingsscript Haiku ↔ llama3.1:8b op een vaste set onderwerpen.
3. **Agent:** in de app een `HubSummaryClient` naast `AnthropicClient`, met een instelling voor de hub-URL en het token (Keychain), een korte time-out en de terugvalketen hub → (optioneel Claude) → `localSummary`. Plus unit-tests op het contract en op de terugval.

## Drift (vastgelegd, niet opgepakt)

- `Info.plist` heeft `NSAllowsArbitraryLoads = true` (`FableFlux/Info.plist:38-42`). Dat staat haaks op "uitsluitend `https://` en ATS aan" in `IOS_Swift.md`. Het staat los van #237, want de hub kan gewoon https gebruiken. Voorstel: apart issue.
- De hub zou de feeds ook zelf kunnen ophalen en de samenvatting vooraf klaarzetten. Dat valt buiten Optie B ("de app blijft zelf feeds ophalen") en is hier niet uitgewerkt.
