# Projectbrief — FableFlux

**Datum:** 2026-07-22
**Status:** herijkt op 2026-07-22

## Doel
Een native iOS RSS-lezer die nieuws per onderwerp samenvat met AI (Claude API), gebouwd voor eigen gebruik. Reden om zelf te bouwen: geen bestaande RSS-lezer maakte samenvattingen per onderwerp naar wens. De app wordt dagelijks gebruikt (ochtend en late middag) voor zowel de Mastodon social feed als losse RSS-feeds.

Het project draait nu om één koersverschuiving: **de AI-samenvatting moet de hoofdpagina van de app worden**, in plaats van een bijzaak. De huidige samenvatting is "te mager" en moet uitgebreider én betrouwbaarder.

## Gewenste uitkomst
Een samenvatting die het startpunt van de app is en waarin je kunt navigeren:

- De samenvatting is de **hoofdpagina** — het eerste wat je ziet.
- Uitgebreider en betrouwbaarder dan nu.
- **Inline bronverwijzingen**: vanuit de samenvatting naar de onderliggende feed/het artikel springen, en weer terug.
- Bronanalyse en fact-check (bestaan al in de app) spelen een rol in de betrouwbaarheid van de samenvatting. De samenvatting bestaat doorgaans uit meerdere behandelde onderwerpen; de betrouwbaarheidsduiding hangt **per onderwerp**, niet aan de samenvatting als geheel:
  - **Bronduiding per onderwerp** op twee assen — betrouwbaarheid (high/mixed/low) én politieke kleur (bias, −2 links … +2 rechts). Bijv. "dit onderwerp: overwegend rechtse bronnen, hoge betrouwbaarheid".
  - Per losse bron/artikel blijft betrouwbaarheid + kleur zichtbaar via de inline bronverwijzingen.
  - **Duiden, niet weglaten** — ook minder betrouwbare bronnen worden getoond en geduid, nooit stil uit de samenvatting verwijderd.
  - **Fact-check-waarschuwing per onderwerp** — bij het onderwerp waaronder een betwijfelde bewering valt.

"Klaar" is bereikt wanneer de samenvatting een betrouwbaar overzicht geeft van de belangrijkste ontwikkelingen op het onderwerp van die samenvatting.

## Scope
**Wel:**
- Native iOS-app voor eigen gebruik.
- Mastodon social feed én losse RSS-feeds.
- AI-samenvatting per onderwerp als hoofdpagina, met inline bronverwijzingen.
- Bronanalyse en fact-check als onderdeel van de betrouwbaarheid.

**Niet:**
- Geen iPad-versie.
- Geen App Store-distributie.
- Geen ondersteuning voor andere gebruikers dan de maker zelf.

Er zijn verder geen features die nu bewust worden weggelaten.

## Doelgroep / belanghebbenden
Uitsluitend de maker, als enige gebruiker en beslisser. Een persoonlijk project zonder externe belanghebbenden.

## Succescriteria
- De samenvatting geeft een overzicht van de belangrijkste ontwikkelingen op het onderwerp van de samenvatting.
- De samenvatting is uitgebreider en betrouwbaarder dan de huidige, "te magere" versie.
- Vanuit de samenvatting is de bron (feed/artikel) direct te bereiken en terug te navigeren.
- Bij dagelijks gebruik (ochtend + late middag) is de app een bruikbaar startpunt voor het nieuws.

## Requirements
Afgeleid van de gewenste uitkomst; geprioriteerd volgens MoSCoW. Elke actionable eis is belegd als (sub-)issue; zie de kolomverwijzing.

### Must — zonder dit is de oplevering niet bruikbaar
- R1: De AI-samenvatting is het eerste scherm bij het openen van de app (hoofdpagina) — reden: kern van de herijkte koers, de samenvatting ís het product. (sub-issue onder #14)
- R2: De samenvatting groepeert het nieuws per behandeld onderwerp — reden: alle duiding en navigatie hangt op onderwerp-niveau. (sub-issue onder #14)
- R3: Vanuit de samenvatting kan de gebruiker naar de onderliggende feed/het artikel navigeren én terugkeren (inline bronverwijzingen) — reden: verifieerbaarheid en het besloten heen/terug-navigeren. (sub-issue onder #14)
- R11: Elke bewering in de samenvatting is herleidbaar naar minstens één gelinkte bron (geen ongefundeerde beweringen) — reden: maakt "betrouwbaarder" toetsbaar. (sub-issue onder #14)
- R8: De feeds blijven volledig leesbaar wanneer de AI niet beschikbaar is (geen sleutel, API onbereikbaar, fout) — reden: harde randvoorwaarde; de app mag niet onbruikbaar worden zonder AI. (#15) — **geverifieerd op device (2026-07-29): structureel geborgd; RSS-refresh is Claude-onafhankelijk en elke AI-faalroute valt terug op `localSummary`.**

### Should — belangrijk, maar niet fataal bij uitstel
- R4: Per onderwerp toont de app een bronduiding op twee assen — betrouwbaarheid (high/mixed/low) en politieke kleur (bias −2…+2) — reden: kern van de betrouwbaarheidsduiding, maar de hoofdpagina functioneert er ook zonder. (sub-issue onder #11)
- R6: Minder betrouwbare bronnen worden getoond en geduid, niet uit de samenvatting weggelaten — reden: de lezer moet zelf kunnen wegen; weglaten verbergt wat mist. (sub-issue onder #11)
- R7: Bij een onderwerp met een betwijfelde bewering toont de app een fact-check-waarschuwing — reden: versterkt betrouwbaarheid; hangt af van herstel fact-check (#13). (sub-issue onder #11)
- R10: Per onderwerp behandelt de samenvatting de belangrijkste ontwikkelingen op basis van minimaal 2 onderliggende bronnen waar er meerdere beschikbaar zijn — reden: maakt "uitgebreider" toetsbaar. (sub-issue onder #14)
- R12: De gebruiker kan per feed instellen of deze meetelt in de AI-samenvatting; uitgesloten feeds blijven gewoon leesbaar in Artikelen en Bewaard — reden: voorkomt dat een feed die niet relevant is voor het nieuwsoverzicht de samenvatting verwatert, zonder de feed te hoeven verwijderen; de hoofdpagina functioneert ook zonder deze instelling. (#68)

### Could — meerwaarde als er ruimte is
- R5: Per losse bron/artikel zijn betrouwbaarheid en politieke kleur zichtbaar via de bronverwijzing — reden: detailverdieping bovenop de duiding per onderwerp. (sub-issue onder #11)
- R9: Het aantal Claude-API-calls per samenvatting blijft binnen een nader te bepalen kostenkader — reden: kostenbeheersing; het kader moet eerst onderzocht worden (#12). (#12)

### Won't — nu bewust niet (sluit aan op Scope → Niet)
- Geen iPad-versie — reden: persoonlijk iOS-gebruik, geen behoefte.
- Geen App Store-distributie — reden: uitsluitend eigen gebruik.
- Geen ondersteuning voor andere gebruikers dan de maker — reden: persoonlijk project zonder externe belanghebbenden.

## Randvoorwaarden & aannames
- **Techniek:** native iOS (iOS 17+, Xcode 15+, Swift 5.9+), SwiftData, uitsluitend Apple-frameworks. AI via de Anthropic REST API (`claude-haiku-4-5`); API-sleutel in de Keychain.
- **API-kostprijs speelt een rol:** de kosten van de Claude API wegen mee in hoe ver uitgebreidere en vaker ververste samenvattingen mogen gaan. Uitgebreider mag niet onbeperkt duurder worden.
- **Offline/AI-uitval is een harde eis:** als de AI niet beschikbaar is (geen sleutel, API onbereikbaar, fout), moeten de feeds nog steeds gewoon leesbaar zijn. De AI-samenvatting is de hoofdpagina, maar mag geen blokkade vormen voor het basisgebruik.
- **Aanname:** de bestaande bronanalyse- en fact-check-functionaliteit is een geschikte basis om op voort te bouwen (zie ook het openstaande punt over hun precieze rol).
- **Risico:** een uitgebreidere samenvatting verhoogt zowel API-kosten als de kans op onbetrouwbaarheid; betrouwbaarheid en kosten moeten tegen elkaar worden afgewogen.

## Genomen besluiten
- De AI-samenvatting wordt de hoofdpagina van de app — reden: dit is de belangrijkste behoefte en de aanleiding om zelf te bouwen; de huidige samenvatting is te mager.
- De samenvatting krijgt inline bronverwijzingen (heen en terug navigeren naar feed/artikel) — reden: betrouwbaarheid en verifieerbaarheid; vanuit het overzicht direct naar de bron kunnen.
- Scope blijft puur iOS voor eigen gebruik: geen iPad, geen App Store, geen andere gebruikers — reden: persoonlijk project, geen distributiebehoefte.
- Feeds moeten leesbaar blijven zonder werkende AI — reden: de app mag niet onbruikbaar worden als de API wegvalt.
- De API-kostprijs weegt mee in de mate van uitbreiding/verversing — reden: kosten beheersbaar houden bij een uitgebreidere samenvatting.
- Bronanalyse en fact-check landen **per behandeld onderwerp** in de samenvatting, niet op de samenvatting als geheel — reden: een samenvatting bundelt meerdere onderwerpen; betrouwbaarheid verschilt per onderwerp en moet daar zichtbaar zijn.
- Beide assen van de bronanalyse tellen mee: betrouwbaarheid én politieke kleur — reden: naast "hoe betrouwbaar" is ook "vanuit welke hoek belicht" relevant voor het inschatten van een onderwerp.
- **Duiden in plaats van weglaten**: minder betrouwbare bronnen worden getoond en geduid, niet stil uit de samenvatting verwijderd — reden: weglaten verbergt dat er iets mist; de lezer moet zelf kunnen wegen.
- Fact-check uit zich als een **waarschuwing per onderwerp** bij betwijfelde beweringen — reden: consistente granulariteit met de bronduiding, zonder de samenvatting te blokkeren.
- De koppeling samenvatting→bron (R3/R11) gebeurt via **gestructureerde generatie**: het model levert beweringen met bron-ids, niet inline-tekstmarkers of achteraf-matchen — reden: maakt "elke bewering herleidbaar" (R11) structureel afdwingbaar en draagt later ook de bronduiding per onderwerp (R4) en de fact-check-waarschuwing (R7) per bewering/onderwerp.
- Beweringen citeren bronnen **hybride** (#33): synthese waar bronnen elkaar overlappen (meerdere bron-ids per bewering), anders enkelvoudig — reden: toont brede dekking waar die er is en behoudt tegelijk directe herleidbaarheid; de prompt stuurt hier expliciet op.

## Herziene besluiten
- Openstaand punt "precieze rol van bronanalyse en fact-check" (vorige brief) — vervalt: de rol is nu belegd (zie besluiten hierboven en Gewenste uitkomst). Resteert alleen de weergavevorm (matrix, zie Richting).

## Openstaande punten
> Vast te leggen als issue.

_Geen openstaande punten meer._

- ~~Hoe "uitgebreider en betrouwbaarder" concreet wordt begrensd tegen de API-kostprijs~~ — **opgelost** (#12), zie **Kostenkader** hieronder.

## Kostenkader (R9 / #12)
Onderzoek 2026-07-29. Prijs `claude-haiku-4-5`: **$1,00/1M input, $5,00/1M output** (bron: Anthropic first-party tarief via de claude-api-skill, cache 2026-06-24).

Kostenstructuur: **1 API-call per onderwerp-cluster** per refresh; input ≈ ~1.500 tokens/call (max 10 artikelen), output begrensd door `SummaryLength.maxTokens` (300/600/1000). Bij dagelijks gebruik (ochtend + late middag, ~2 refreshes/dag, ~5 clusters):

| Scenario | Per refresh | Per maand |
|----------|-------------|-----------|
| Normaal (600 out) | ~$0,022 | ~€1,35 |
| Uitgebreid (1000 out) | ~$0,030 | ~€1,80 |
| Zwaar (8 clusters, uitgebreid, 4×/dag) | ~$0,052 | ~€6,30 |

**Conclusie:** bij eigen gebruik zijn de kosten verwaarloosbaar (enkele euro's/maand). Het kader dient om ongemerkte groei te begrenzen.

**Vastgelegde grenzen:**
1. **Max 10 artikelen per call** (`AppConfiguration.maxArticlesPerSummary`) — begrenst input.
2. **Output-cap** via `SummaryLength.maxTokens` (300/600/1000) — reeds aanwezig.
3. **Verversings-debounce ≥ 2 min** (`clusteringDebounce`, nu 120s) — voorkomt call-stormen.
4. **Richtbudget < €10/maand** bij normaal gebruik — ruime marge; geen harde in-app-limiet nodig.
5. **Prompt-caching niet toegepast** — elke cluster-call heeft een unieke artikellijst; geen deelbare prefix, dus geen besparing.

## Richting, nog geen besluit
- **Matrix (politieke kleur × betrouwbaarheid)** als concrete weergavevorm van de bronduiding per onderwerp — als richting genoemd ("wellicht een matrix"), vorm nog niet vastgesteld.
- Inline bronlink als vorm van zelfverificatie (lezer controleert de bron zelf) — als richting genoemd, nog niet definitief vastgesteld.
- Tegenspraak tussen bronnen expliciet tonen in de samenvatting — voorstel uit het gesprek, niet bevestigd.

## Voorgestelde vervolgstappen
1. De samenvatting-hoofdpagina ontwerpen: uitgebreidere inhoud met inline bronverwijzingen (heen/terug-navigatie) en **per onderwerp** een bronduiding (betrouwbaarheid + politieke kleur) en fact-check-waarschuwing.
2. De weergavevorm van de bronduiding per onderwerp bepalen — matrix (kleur × betrouwbaarheid) of een andere vorm (zie Richting).
3. ~~Een kostenkader bepalen voor de samenvatting~~ — **gedaan** (#12), zie sectie **Kostenkader**.
4. ~~De offline/AI-uitval-eis borgen: feeds blijven leesbaar zonder werkende AI~~ — **gedaan** (#15): op device geverifieerd, geen afwijkingen.
5. De bestaande fact-check-fout onderzoeken (ontbrekend veld `claims` in de API-response) voordat fact-check een grotere rol in de samenvatting krijgt.
