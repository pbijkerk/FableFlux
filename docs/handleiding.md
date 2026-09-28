# FableFlux — gebruikershandleiding

FableFlux is een nieuwslezer voor de iPhone. De app
haalt RSS- en Atom-feeds, podcasts, videokanalen en je Mastodon-tijdlijn op. Die artikelen
groepeert hij per onderwerp, en elke ochtend (of wanneer je wilt) krijg je een samenvatting van
wat er de afgelopen twee dagen speelde.

---

## Inhoud

1. [Eerste keer opstarten](#1-eerste-keer-opstarten)
2. [De drie tabbladen](#2-de-drie-tabbladen)
3. [Vandaag: de samenvatting](#3-vandaag-de-samenvatting)
4. [Artikelen](#4-artikelen)
5. [Een artikel lezen](#5-een-artikel-lezen)
6. [Bewaard](#6-bewaard)
7. [Feeds beheren](#7-feeds-beheren)
8. [Mappen](#8-mappen)
9. [Onderwerpen](#9-onderwerpen)
10. [Mastodon](#10-mastodon)
11. [Bronanalyse en fact-check](#11-bronanalyse-en-fact-check)
12. [Instellingen](#12-instellingen)
13. [Veelgestelde vragen](#13-veelgestelde-vragen)

---

## 1. Eerste keer opstarten

Een nieuwe installatie is leeg. Drie stappen om te beginnen:

1. **Feeds toevoegen.** Ga naar **Artikelen** en tik op **Feeds beheren**. Voeg losse feeds toe
   via hun adres, of importeer in één keer een OPML-bestand uit een andere RSS-lezer
   (zie [Feeds beheren](#7-feeds-beheren)).
2. **Optioneel: een Claude API-sleutel invullen.** Zonder sleutel maakt de app de samenvattingen
   zelf, op het toestel. Met een sleutel schrijft Claude ze; die zijn beter leesbaar en
   combineren de berichtgeving van meerdere bronnen. Zie [Samenvattingen](#samenvattingen).
3. **Optioneel: Mastodon koppelen.** Je tijdlijn verschijnt dan als gewone feed
   (zie [Mastodon](#10-mastodon)).

Bij elke start ververst de app alle feeds en maakt daarna een nieuwe samenvatting.

---

## 2. De drie tabbladen

Onderin het scherm zweeft een tabbalk met drie tabbladen:

| Tabblad | Wat je er ziet |
|---|---|
| **Vandaag** | De samenvatting per onderwerp van de afgelopen 48 uur. Hier opent de app. |
| **Artikelen** | Alle artikelen uit al je feeds, nieuwste eerst, met een filter per map. |
| **Bewaard** | Artikelen die je voor later hebt bewaard. |

**Instellingen** open je met het tandwiel rechtsboven op **Vandaag**. Het instellingenscherm
sluit je met **Gereed**.

---

## 3. Vandaag: de samenvatting

**Vandaag** toont per onderwerp een kaart met de belangrijkste ontwikkelingen. Zo is een kaart
opgebouwd:

- **Kop:** de naam van het onderwerp en het aantal bronnen dat erover schreef. Tik op de kop
  voor de detailpagina met alle artikelen van dat onderwerp.
- **Beweringen:** korte uitspraken over wat er gebeurd is. Onder elke bewering staan
  **bronchips**, één per artikel waar de bewering op steunt. Een chip toont de titel van het
  artikel en de feednaam. Tik erop om dat artikel te openen. Elke bewering heeft minstens één
  bron. Een bewering zonder bron wordt nooit getoond.
- **Toon meer / Toon minder:** een kaart toont eerst drie beweringen. Heeft het onderwerp er
  meer, dan klap je de rest hiermee uit.
- **Bronduiding:** de politieke kleur van de bronnen samen ("overwegend …") en hun
  betrouwbaarheid. Bronnen zonder beoordeling tellen niet mee.
- **Fact-checkwaarschuwing:** een melding *"Bevat een betwijfelde bewering"* verschijnt als een
  onafhankelijke factchecker een bewering uit een van de artikelen heeft betwist. Tik erop voor
  de details (zie [Fact-check](#fact-check)).

### Verversen
Trek de lijst naar beneden (pull-to-refresh). De app ververst dan alle feeds en maakt direct een
nieuwe samenvatting. Wanneer de app zelf ververst, bijvoorbeeld bij het opstarten, maakt hij
hooguit één keer per twee minuten een nieuwe samenvatting. Bij zelf verversen geldt die grens
niet.

### Welke artikelen tellen mee?
- Alleen artikelen van de **afgelopen 48 uur**. Oudere artikelen blijven gewoon in
  **Artikelen** en **Bewaard** staan.
- Alleen feeds met **Meenemen in samenvatting** aan (standaard aan; zie
  [Feedinstellingen](#instellingen-per-feed)).
- Alleen artikelen die op een **onderwerp** passen. Een artikel dat op geen enkel onderwerp
  past, komt niet in de samenvatting (zie [Onderwerpen](#9-onderwerpen)).

Is de pagina leeg, dan is er in die 48 uur niets binnengekomen dat meetelt. Het scherm legt dat
ook zelf uit.

### De detailpagina van een onderwerp
Tik op de kop van een kaart. Je ziet dan de volledige samenvatting en de lijst met alle
artikelen van dat onderwerp. Staat het onderwerp nog niet bij je onderwerpen, dan vraagt de
banner onderin *"Interessant onderwerp?"*. Met **Favoriet maken** wordt het een favoriet
onderwerp. Dat komt dan bovenaan op **Vandaag** te staan (zie
[Favoriete onderwerpen](#favoriete-onderwerpen)).

---

## 4. Artikelen

**Artikelen** toont alle artikelen uit al je feeds, nieuwste bovenaan. Tijdens het scrollen
laadt de lijst er steeds vijftig bij.

- **Mapfilter:** als je mappen hebt, staat bovenaan een balk met **Alle** en een knop per map.
  Je keuze blijft bewaard, ook na het afsluiten van de app.
- **Vernieuwen:** de pijl linksboven, of trek de lijst naar beneden.
- **Feeds beheren:** via de **+** rechtsboven.

### Veeggebaren op een artikel

| Gebaar | Actie |
|---|---|
| Naar **rechts** vegen | **Bewaar** (of **Niet bewaard** als het al bewaard is) |
| Naar **links** vegen | Markeer als **Gelezen** of **Ongelezen** |

Een artikel geldt als gelezen zodra je het opent. Staat **Verberg gelezen artikelen** aan (zie
[Weergave](#weergave)), dan verdwijnt het daarna uit de lijst.

### Een artikelkaart
Een kaart toont de bron en hoe lang geleden het artikel verscheen, de titel, een paar regels
voorvertoning en eventueel een miniatuurafbeelding. Een symbool geeft aan of het om een video
(▶) of podcast (golfvorm) gaat, en een bladwijzer of je het bewaard hebt. Staat de bronanalyse
aan, dan zie je daaronder de politieke positie, de betrouwbaarheid en een eventuele fact-check
van de bron.

---

## 5. Een artikel lezen

Tik op een artikel om het te openen.

- **Bladeren:** veeg horizontaal naar het vorige of volgende artikel uit dezelfde lijst.
- **Leesvoortgang:** een dun lijntje bovenin loopt mee terwijl je scrolt.
- **Volledig artikel:** een feed bevat vaak alleen een inleiding. Tik op de titel
  (*"Tik voor het volledige artikel ›"*): de app haalt dan de hele tekst van de website op en
  toont die in dezelfde leesweergave. Lukt dat niet, dan verschijnt rechtsboven
  **Opnieuw laden**.
- **Links** in de tekst openen in een browser binnen de app.

### Knoppen rechtsboven
| Knop | Actie |
|---|---|
| Bladwijzer | Bewaren of uit **Bewaard** halen |
| Kompas | **Open in browser**: de originele webpagina, binnen de app |
| Deelknop | **Delen** via het iOS-deelmenu |

Bij een artikel zonder link, zoals een Mastodon-bericht zonder externe verwijzing, zie je alleen
de bladwijzer.

### Podcasts en video
- **Podcast:** bovenin staat een audiospeler met afspeelknop, voortgangsbalk en resterende tijd.
  De beschrijving van de aflevering staat eronder.
- **YouTube en Vimeo:** tik op **Tik om af te spelen**. De video opent in een speler binnen de
  app.
- **Directe video (bijv. MP4):** speelt af in de ingebouwde iOS-videospeler.

### Bronstrook
Heeft de bron een beoordeling, dan staat boven het artikel een strook met de politieke positie
en de betrouwbaarheid. Tik op de balk voor **Over deze bron** (zie
[Bronanalyse](#bronanalyse)).

---

## 6. Bewaard

Hier staan alle artikelen die je bewaard hebt. Bewaren doe je door een artikel naar rechts te
vegen of met de bladwijzer in het artikel.

- Veeg naar links en tik op **Verwijder** om een artikel uit **Bewaard** te halen.
- Bewaarde artikelen vallen buiten de [bewaarperiode](#artikelen-bewaren): de app ruimt ze
  nooit automatisch op. Verwijder je de feed zelf, dan verdwijnen ook de bewaarde artikelen
  van die feed.

---

## 7. Feeds beheren

Ga naar **Artikelen → + → Feeds beheren**. Je feeds staan daar gegroepeerd per map. Feeds zonder
map staan onder **Overig**.

Per feed zie je het icoon van de website, de naam, het adres, een teller en hoe lang geleden de
feed voor het laatst ververst is. Tik op een feed voor de artikelen van alleen die feed.

### Een feed toevoegen
1. Tik op **+ → Feed toevoegen**.
2. Vul het adres van de feed in, bijvoorbeeld `nos.nl/feeds/...`. `https://` mag je weglaten.
3. Tik op **Feed toevoegen**. De app controleert of het adres een geldige feed is, neemt de naam
   over en haalt direct de artikelen op.

Video- en podcastfeeds (YouTube, Vimeo, podcasts) herkent de app zelf.

### OPML importeren
Een OPML-bestand is een exportbestand met feeds, uit vrijwel elke andere RSS-lezer te halen.

1. Tik op **+ → OPML importeren → Bestand kiezen** en kies het bestand (bijvoorbeeld uit
   Bestanden of iCloud Drive).
2. Je krijgt een lijst van alle gevonden feeds. Feeds die je al hebt, zijn gemarkeerd met
   *Al toegevoegd*. Vink aan wat je wilt (**Alles selecteren** / **Niets selecteren**).
3. Tik op **Importeer (n)**.

De mapindeling uit het OPML-bestand wordt overgenomen.

### Acties per feed

| Gebaar | Actie |
|---|---|
| Naar **rechts** vegen | **Vernieuwen**: alleen deze feed |
| Naar **links** vegen | **Verwijderen**: de feed en al zijn artikelen, na bevestiging |
| Lang indrukken | **Verplaats naar folder** en **Instellingen** |

### Instellingen per feed
Houd een feed ingedrukt en kies **Instellingen**:

- **Meenemen in samenvatting**: staat deze uit, dan telt de feed niet meer mee op **Vandaag**.
  De artikelen blijven wel zichtbaar in **Artikelen** en **Bewaard**. Handig voor feeds die de
  samenvatting vervuilen, zoals aanbiedingen of een drukke Mastodon-tijdlijn. **Vandaag** past
  zich direct aan.
- **Bewaarperiode**: hoe lang artikelen van deze feed bewaard blijven. **Gebruik standaard**
  volgt de algemene instelling. **Nooit** bewaart alles. Een kortere periode ruimt oudere
  artikelen direct op.

Tik op **Gereed** om op te slaan.

### Teller
De teller naast een feed toont het totale aantal artikelen, of alleen het aantal ongelezen
artikelen. Dat kies je in [Weergave](#weergave).

---

## 8. Mappen

Met mappen groepeer je feeds, bijvoorbeeld *Nieuws*, *Tech* of *Podcasts*. Ze komen terug als
filter in **Artikelen** en als secties in **Feeds beheren**.

- **Map aanmaken, hernoemen of verwijderen:** **Feeds beheren → + → Folders beheren**. Veeg een
  map naar links voor **Hernoemen** en **Verwijderen**, of houd hem ingedrukt. Verwijder je een
  map, dan gaan de feeds erin naar **Overig**. De feeds zelf blijven bestaan.
- **Volgorde:** tik in **Folders beheren** op **Volgorde**, of kies in **Feeds beheren**
  **+ → Volgorde wijzigen**, en sleep de mappen.
- **Feed in een map zetten:** houd de feed ingedrukt → **Verplaats naar folder**.
- **In- en uitklappen:** tik op het aantal met het pijltje naast de mapnaam.
- **Systeemmap:** de map **Social**, met je Mastodon-tijdlijnen, maakt de app zelf aan. Die kun
  je niet hernoemen of verwijderen.

### Een map openen: Gebeurtenissen
Tik in **Feeds beheren** op de naam van een map. Je ziet dan alle artikelen van die map. Met de
schakelaar rechtsboven kies je tussen twee weergaven:

- **Tijdlijn** (lijstje): alle artikelen op volgorde.
- **Gebeurtenissen** (gestapelde lagen): artikelen over hetzelfde voorval, gegroepeerd. Per
  groep zie je hoeveel artikelen en hoeveel bronnen erover schreven, en welke politieke posities
  die bronnen innemen. Zo zie je in één oogopslag hoe verschillende media hetzelfde nieuws
  brengen.

---

## 9. Onderwerpen

Onderwerpen bepalen hoe **Vandaag** is ingedeeld. Een onderwerp is een naam plus een lijst
trefwoorden. Een artikel komt bij het onderwerp waarvan het de meeste trefwoorden bevat.

### Standaardonderwerpen
De app heeft acht ingebouwde onderwerpen: *Kunstmatige intelligentie, Technologie, Politiek,
Wetenschap, Economie, Sport, Gezondheid* en *Cultuur & media*. Ze herkennen zowel Nederlandse als
Engelse artikelen. De naam volgt de taal van de samenvatting (zie
[Samenvattingen](#samenvattingen)): staat die op *English*, dan heet Politiek *Politics*.

Een artikel dat op geen enkel onderwerp past, komt niet in de samenvatting. Mis je een
onderwerp, maak dan een eigen onderwerp aan.

Geef je een eigen onderwerp dezelfde naam als een ingebouwd onderwerp, bijvoorbeeld *Sport*, dan
vervangt het dat ingebouwde onderwerp. Het houdt je eigen trefwoorden en krijgt die van het
ingebouwde onderwerp erbij. Zo staat er nooit twee keer een kaart *Sport* op Vandaag.

### Eigen onderwerpen
**Instellingen → Onderwerpen → Onderwerpen beheren → +**

1. Geef het onderwerp een **naam**, bijvoorbeeld *Klimaat*.
2. Voeg **trefwoorden** toe, bijvoorbeeld *klimaat*, *CO2*, *stikstof*, *emissie*. De app zoekt
   op hele woorden en woordgroepen, zonder onderscheid tussen hoofd- en kleine letters.
   *ai* past dus op "AI", maar niet op "email".
3. Zet eventueel **Markeer als favoriet** aan.
4. Tik op **Bewaren**.

In de lijst veeg je een onderwerp naar rechts voor **Favoriet maken** / **Favoriet
verwijderen**, en naar links voor **Verwijderen**. Tik op een onderwerp om het te bewerken.

### Favoriete onderwerpen
Een favoriet onderwerp krijgt voorrang: het staat bovenaan op **Vandaag**, met een hartje voor
de naam. Daaronder volgen de andere onderwerpen, gesorteerd op het aantal artikelen. Alle
onderwerpen blijven meedoen: je eigen onderwerpen en de ingebouwde onderwerpen.

Favoriet maken kan op drie manieren:
- op de detailpagina van een onderwerp, met **Favoriet maken**
- in **Onderwerpen beheren**, door een onderwerp naar rechts te vegen
- bij het bewerken van een onderwerp, met **Markeer als favoriet**

---

## 10. Mastodon

**Instellingen → Mastodon → Mastodon-account toevoegen**

1. Vul het domein van je Mastodon-server in, bijvoorbeeld `mastodon.social` of `fosstodon.org`.
2. Tik op **Verbinden met Mastodon**. Je logt in op de website van je server en geeft FableFlux
   toestemming om te lezen.
3. Daarna zie je **Verbonden** met je accountnaam. Tik op **Gereed**.

Je tijdlijn verschijnt als feed in de map **Social**, inclusief boosts en afbeeldingen. Berichten
met een inhoudswaarschuwing (CW) zijn ingeklapt; tik erop om de tekst te tonen. Je kunt meerdere
accounts koppelen.

- **Account verwijderen:** veeg het account naar links in **Instellingen → Mastodon**. De
  bijbehorende feed verdwijnt mee.
- **Oranje waarschuwingsdriehoek** naast een account: de toegang is verlopen of ingetrokken.
  Voeg het account opnieuw toe via **Mastodon-account toevoegen**. De app herkent het account
  en werkt het bij. Je tijdlijn en bewaarde berichten blijven staan.

Tip: een drukke tijdlijn overheerst de samenvatting al snel. Zet **Meenemen in samenvatting**
voor die feed uit als je dat niet wilt.

---

## 11. Bronanalyse en fact-check

### Bronanalyse
Voor ruim honderd bekende nieuwsbronnen heeft de app een beoordeling aan boord, gebaseerd op
onafhankelijke organisaties als AllSides en Media Bias/Fact Check:

- **Politieke positie**, op een balk van *Links* via *Centrum* tot *Rechts*.
- **Feitelijke betrouwbaarheid**, als schildje: *Hoog* (groen), *Gemiddeld* (amber) of *Laag*.

Tik op de balk voor **Over deze bron**: de beoordeling, wie die maakte en wanneer. Een
beoordeling gaat over de nieuwsbron als geheel, niet over het ene artikel. Bronnen zonder
beoordeling krijgen geen balk. De app raadt nooit een beoordeling.

Uitzetten: **Instellingen → Bronanalyse & Fact-check → Toon bronanalyse op artikelkaarten**.

### Fact-check
Met een sleutel voor de **Google Fact Check API** controleert de app van elk artikel dat je
opent of factcheckers er beweringen uit hebben beoordeeld.

- Op de artikelkaart verschijnt dan **Fact-checked · \<beoordelaar\>**. Klap die uit voor de
  bewering, het oordeel, de beoordelaar en een link **Bekijk beoordeling →**.
- Is een bewering als onjuist of misleidend beoordeeld, dan toont **Vandaag** bij dat onderwerp
  *"Bevat een betwijfelde bewering"*.
- Een uitslag blijft zeven dagen geldig; daarna controleert de app opnieuw.

De sleutel vul je in bij **Instellingen → Bronanalyse & Fact-check**. Een sleutel maak je aan in
de Google Cloud Console, door daar de *Fact Check Tools API* in te schakelen. Zonder sleutel
doet de fact-check niets. De rest van de app werkt dan gewoon.

---

## 12. Instellingen

Open **Instellingen** met het tandwiel op **Vandaag**.

### Uiterlijk
Kies een van zeven FableFlux-logo's: *Origineel, Oceaan, Nacht, Kampvuur, Inkt, Woud* of
*Perkament*. Het app-icoon op je beginscherm verandert mee, net als de accentkleur in de app.
iOS toont daarbij zelf een melding dat het icoon is gewijzigd. Lukt het wisselen van het icoon
niet, tik dan nog een keer op hetzelfde logo.

### Weergave
| Instelling | Wat het doet |
|---|---|
| Verberg gelezen artikelen | Gelezen artikelen verdwijnen uit de lijsten |
| Toon miniatuurafbeeldingen | Afbeeldingen in de artikellijst aan of uit |
| Teller per feed | *Totaal aantal artikelen* of *Ongelezen artikelen* |
| Regels voorvertoning | 1 tot 5 regels tekst per artikel in de lijst |

### Tekstgrootte
Drie schuifregelaars van 80% tot 150%: **Feeds-lijst**, **Artikelen** (de leestekst) en
**Bronanalyse**. Daarnaast kies je het **lettertype voor artikelen**: *Charter* (standaard),
*SF Pro*, *New York* of *Georgia*. **Herstel standaardwaarden** zet de drie regelaars terug op
100%. Alle tekst schaalt daarnaast mee met de tekstgrootte die je in iOS hebt ingesteld.

### Samenvattingen
| Instelling | Wat het doet |
|---|---|
| Taal | *Nederlands* of *English* |
| Lengte | *Kort* (2–3 zinnen), *Normaal* (4–6) of *Uitgebreid* (8–10) |
| Claude API-sleutel | Laat Claude de samenvattingen schrijven |

**Zonder sleutel** maakt de app de samenvatting zelf, op het toestel, uit de artikelteksten. Er
gaat dan niets naar buiten.

**Met sleutel** gaan de titels en beschrijvingen van de artikelen per onderwerp naar Claude
(Anthropic), dat er een samenvatting met bronverwijzingen van maakt. Dat kost een klein bedrag
per samenvatting, dat Anthropic afrekent op het account van de sleutel.

Een sleutel aanvragen:
1. Tik op **Claude API-sleutel aanvragen**. De console van Anthropic opent.
2. Maak een account aan, stel betaling in en maak een API-sleutel aan (begint met `sk-ant-`).
3. Plak de sleutel in het veld. Met het oogje maak je hem zichtbaar.

Onder het veld zie je de stand:

| Melding | Betekenis |
|---|---|
| Lokale samenvattingen | Geen sleutel ingevuld |
| Sleutel valideren… | De app controleert de sleutel |
| **AI-samenvattingen actief** (groen) | Sleutel werkt |
| Sleutel ongeldig of verlopen (rood) | Anthropic weigert de sleutel; maak een nieuwe aan |
| Kon niet valideren — controleer je verbinding | Geen verbinding; de sleutel is wel opgeslagen |

Sleutels worden in de iOS-sleutelhanger (Keychain) opgeslagen en nergens anders.

### Bronanalyse & Fact-check
Zie [Bronanalyse en fact-check](#11-bronanalyse-en-fact-check).

### Artikelen bewaren
**Standaard bewaarperiode**: hoe lang artikelen blijven staan voordat de app ze opruimt. Kies
uit 1 dag tot 1 jaar, of **Nooit**. Standaard is dat 30 dagen. Feeds met een eigen bewaarperiode
volgen hun eigen instelling. Bewaarde artikelen worden nooit opgeruimd. De wijziging gaat in bij
de volgende verversing.

### Onderwerpen en Mastodon
Zie [Onderwerpen](#9-onderwerpen) en [Mastodon](#10-mastodon).

### Over
De naam van de app en het versienummer.

---

## 13. Veelgestelde vragen

**Vandaag is leeg, maar Artikelen staat vol.**
Vandaag kijkt 48 uur terug en toont alleen artikelen die op een onderwerp passen. Controleer of
er recente artikelen zijn en of je onderwerpen bij je feeds passen. Mist er een onderwerp,
maak dan een eigen onderwerp aan (zie [Onderwerpen](#9-onderwerpen)).

**Eén feed overheerst de samenvatting.**
Zet **Meenemen in samenvatting** uit voor die feed (lang indrukken → **Instellingen**).

**De samenvatting ververst niet.**
Automatisch maakt de app hooguit om de twee minuten een nieuwe samenvatting. Trek **Vandaag**
naar beneden om er direct een te maken.

**Een artikel toont alleen een inleiding.**
Tik op de titel om de volledige tekst van de website op te halen. Sommige sites blokkeren dat.
Kies dan **Open in browser**.

**Ik zie geen bias-balk bij een bron.**
Van die bron heeft de app geen beoordeling, of de bronanalyse staat uit in **Instellingen**.

**Werkt de app zonder API-sleutels?**
Ja. Zonder Claude-sleutel maakt de app de samenvattingen zelf. Zonder Google-sleutel is er alleen
geen fact-check.

**Kan ik mijn feeds meenemen naar een andere app?**
Een OPML-export zit nog niet in de app. Importeren kan wel.
