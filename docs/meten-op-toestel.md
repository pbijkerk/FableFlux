# Meten op het toestel (Instruments via de terminal)

Hoe je prestaties van FableFlux meet op een fysieke iPhone met `xctrace`, zonder de
Instruments-app. Opgedaan bij de meting voor #165 (2026-10-04). Alleen op de macOS-werkplek
uitvoerbaar: er zijn Xcode en een aangesloten toestel voor nodig.

## Wat werkt en wat niet

| Aanpak | Resultaat |
| --- | --- |
| `--all-processes` (hele toestel) | Werkt in rust. Onder scrollen valt de verbinding na 1–2 s weg (*end-reason: Device disconnected*). Te veel data. |
| `--attach <naam>` of `--attach <pid>` | Onbetrouwbaar. Vaak *"Cannot find process"*, ook als `devicectl` de PID wel toont. |
| `--launch -- <bundle-ID>` | **Werkt.** Instruments start de app zelf en neemt alleen die op; 6 minuten scrollen zonder onderbreking. |

Gevolg van `--launch`: de app start koud. Wil je een toestand meten die pas na
gebruikersacties ontstaat (bijvoorbeeld 300 geladen rijen), neem dan één doorlopende opname
en knip die achteraf op in fasen, in plaats van een opname per toestand.

## Opname

```bash
xcodegen generate
DEVICE=$(xcrun devicectl list devices \
  | awk '/ physical *$/ && /iPhone/ { for (i = 1; i < NF; i++) if ($(i + 1) == "(UDID)") print $i }' \
  | head -1)
DERIVED=~/Library/Developer/Xcode/DerivedData/FableFlux-device
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
  "$DERIVED/Build/Products/Release-iphoneos/FableFlux.app/Info.plist")

xcrun xctrace record --template 'Time Profiler' --instrument 'Hitches' \
  --device "$DEVICE" --time-limit 360s --output meting.trace \
  --launch -- "$BUNDLE"
```

- **Bouw Release**, zoals in stap 9 van `Workflow-feature.md` (inclusief `-derivedDataPath`
  buiten de projectmap). Een Debug-build is niet geoptimaliseerd en vertekent de
  verhoudingen tussen kostenposten.
- Een Release-build met development-signing heeft `get-task-allow`; profileren mag dus.
- Instrumentnamen verschillen van de sjabloonnamen in de app: het is `Hitches`, niet
  `Animation Hitches`. Controleer met `xcrun xctrace list instruments`.
- Leg het toestel plat neer tijdens de opname; een bewegende kabel kan de verbinding
  verbreken.
- Bewaar `.trace`-bestanden buiten de projectmap (iCloud Drive, en ze zijn groot).

## Fasen herkennbaar maken

- Een tijdelijke teller in de UI (bijvoorbeeld het aantal geladen rijen in de
  `navigationTitle`) laat degene die scrolt zien wanneer een volgende fase begint.
  Niet committen.
- `OSSignposter`-events met categorie `.pointsOfInterest` kwamen bij #165 **niet** in de
  opname, ook niet met het instrument *Points of Interest*. Fasegrenzen zijn toen afgeleid
  uit de SQLite/Core Data-activiteit op de main thread, die alleen bij bijladen optreedt.

## Uitlezen

```bash
xcrun xctrace export --input meting.trace --toc     # welke tabellen er zijn
xcrun xctrace export --input meting.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' > tp.xml
xcrun xctrace export --input meting.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="hitches"]' > hitches.xml
```

- De XML ontdubbelt: een element met `id` komt één keer voluit voor, daarna alleen als
  `ref="…"`. Een parser moet die verwijzingen oplossen.
- `time-profile`: per sample de thread (`fmt` bevat `Main Thread … (FableFlux, pid …)`),
  het gewicht in ns en de backtrace (`frame name=…`, met `binary name=…`). Inclusieve tijd
  van een functie = som van de gewichten van samples waarin die frame voorkomt.
- `hitches`: start en duur in ns, met het proces in `fmt`.
- Het scrolltempo verschilt per fase. Normaliseer daarom niet alleen per seconde maar ook
  per aangemaakte cel (samples met `-[UICollectionView _createPreparedCellForItemAtIndexPath:…]`).
