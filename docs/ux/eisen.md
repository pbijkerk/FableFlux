# UX-eisenkader FableFlux

Opgesteld op 5 november 2026. Hoort bij de schetsen in [`schetsen.html`](schetsen.html): open dat bestand in een browser en gebruik de tabs bovenaan.

| # | Eis | Wetenschappelijke basis | Populaire praktijk |
|---|---|---|---|
| E1 | **Informatiegeur**: in één blik zien of een artikel de moeite waard is (kop, bron, leestijd, beeld) | Information Foraging Theory (Pirolli & Card, 1999) | Rustige scanlijsten van Reeder en NetNewsWire |
| E2 | **Leesweergave**: volledige tekst zonder ruis, instelbare typografie | Regellengte (Dyson & Haselgrove, 2001); Cognitive Load Theory (Sweller, 1988) | Volledige tekst ophalen bij feeds met alleen een samenvatting |
| E3 | **Toegankelijkheid**: Dynamic Type, VoiceOver, contrast ≥ 4,5:1 | WCAG 2.2; donkere tekst op licht leest beter (Piepenbrock e.a., 2013) | Apple HIG |
| E4 | **Duimbediening**: veegacties, belangrijke knoppen onderin | Wet van Fitts (1954); HIG: aanraakzone minimaal 44 pt | "Markeer alles hierboven als gelezen" |
| E5 | **Snelheid en offline lezen** | Doherty-drempel (~400 ms) | Trage sync is de nummer één klacht in reviews |
| E6 | **Geen tellerdruk**: tellers en badges optioneel | Zeigarnik-effect; kosten van onderbrekingen (Mark e.a., 2008); nieuwsmoeheid (Reuters DNR) | Discussie over de tijdlijn in Reeder (2024) |
| E7 | **Controle en beperkte keuze**: geen algoritme, wel filters | Keuzeoverload (Iyengar & Lepper, 2000); zelfdeterminatietheorie | "Mijn bronnen, chronologisch" |
| E8 | **Bekende iOS-patronen**, ongedaan maken, zichtbare status | Nielsen's 10 heuristieken (1994) | Apps die native aanvoelen wekken meer vertrouwen |
| E9 | **Instap en vertrek**: OPML, feed vinden vanaf een gewone URL | Time-to-value bij de eerste keer gebruiken | Overstappen zonder drempel |
| E10 | **Privacy en sync** | Privacy-calculus | Privacylabel in de App Store, geen account nodig |
| E11 | **Beeld bij artikel (indien aanwezig)** | Picture superiority / dual coding (Paivio); eye-tracking: informatieve foto's wel, stockfoto's niet (Nielsen Norman Group) | Apple News, Reeder |

## Gekozen richting (5 nov 2026)

| Volgorde | Scherm | Keuze |
|---|---|---|
| 1 | Later | Lees later (instelbare termijn, standaard 14 dagen) en Bewaard (geen termijn): #224 |
| 2 | Artikelen | 2D Beeld eerst, met de leesmarkering uit 2C: #225 |
| 3 | Lezen | 3A Rustig lezen, met de contextlaag uit 3C: #226 |
| 4 | Vandaag | 1B Verhaallijnen: #227 |

**Geparkeerd:** 1A Ochtendeditie en 1C Aandachtsbudget (later mogelijk als weergave-optie), 3B Samenvatting eerst (later als instelling voor lange artikelen).

**Vervallen:** 2A en 2B gaan op in 2D. 4A en 4B zijn vervangen door het Later-scherm.

## Toetsing

Na elke stap volgt een TestFlight-versie die Peter een week zelf gebruikt. Drie vragen:
1. Worden meer artikelen uitgelezen? (E1, E11)
2. Blijft Lees later klein? (E6)
3. Worden de tellers gemist? (E6)

De koppen, bronnen en afbeeldingen in de schetsen zijn verzonnen voorbeelden. De afbeeldingen zijn kleurvlakken die een foto voorstellen.
