# Belopp

Markera belopp var som helst, i en PDF, ett mejl, en webbsida eller Excel, och räkna med dem direkt i DropClip. Tre knappar under **Belopp**:

## Summera

Summan av alla belopp i markeringen visas direkt på knappen. Klicka för att kopiera den.

Högerklicka (eller ⇧-klicka) för att se antal, medel, min, max och varje belopp som lästes, så att du kan kontrollera summan.

## Moms

Delar upp beloppet både som inklusive och exklusive moms:

- **Inklusive moms:** exkl. moms och momsbeloppet
- **Exklusive moms:** inkl. moms och momsbeloppet

Momssatsen tas från markeringen när den står där (25 %, 12 % eller 6 %), annars från inställningen *Momssats*. Flera belopp summeras först. Exkl. moms och moms går alltid jämnt ihop till öret.

## Valuta

Räknar om med Riksbankens mittkurs för datumet i markeringen, till exempel fakturadatumet. Klicka för att kopiera beloppet; högerklicka för kurs, kursdag och förklaring.

- Valutan läses som kod (EUR, USD, NOK …) eller tecken (€, $, £, ¥).
- Ett belopp i kronor räknas om till valutan i inställningen *Valuta för SEK-belopp*.
- Datum läses som 2026-10-04, 4/10/2026, 4.10.2026 eller 4 okt 2026, alltid dag före månad.
- Utan datum används senaste kursen. Helger och helgdagar har ingen kurs, då används närmast föregående bankdag.
- 29 valutor som Riksbanken publicerar dagligen.

Riksbankens kurser är indikativa. Följ arbetsplatsens rutin om bokföringen kräver en annan kurs.

## Belopp som känns igen

`1 234,50`, `1.234,50`, `1,234.50`, `12 345`, `-500`, `−500`, `(500)` och `500-`. Datum, klockslag, procentsatser och koder som `A123` räknas inte. Kolumner som skiljs åt av tabb eller flera mellanslag hålls isär.

## Inställningar

| Inställning | Standard | |
| --- | --- | --- |
| Kopiera som | Excel: `12345,50` | *Text* ger `12 345,50` |
| Momssats | 25 | när markeringen inte anger någon |
| Valuta för SEK-belopp | EUR | |

## Krav

Valuta hämtar kurser från Riksbankens öppna API (api.riksbank.se) och behöver internet. Summera och Moms räknar helt på datorn.
