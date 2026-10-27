# Obsidian

Markera text var som helst, i ett mejl, en webbsida eller en PDF, och skicka den till ditt Obsidian-valv. Tre knappar under **Obsidian**:

## Till dagens anteckning

Lägger markeringen sist under rubriken *Fångat* i dagens anteckning, med klockslaget först:

```
## Fångat

- 14:32 Ring kunden om fakturan
  Fakturanummer 10234, förfaller fredag
```

- Finns inte dagens anteckning skapas den på samma sätt som i Obsidian: i mappen och med namnformatet och mallen från inställningarna för dagliga anteckningar.
- Finns inte rubriken läggs den till sist i anteckningen.
- Flera rader i markeringen hålls ihop i samma punkt.

## Ny anteckning i inkorgen

Skapar en ny anteckning i mappen för nya anteckningar (till exempel *Inbox*) och öppnar den i Obsidian.

- Namnet är markeringens första rad, högst 60 tecken. Tecken som inte får finnas i ett filnamn tas bort.
- Mallen *Note Template* i mallmappen används om den finns, med `{{title}}`, `{{date}}` och `{{time}}` ifyllda. Under mallen kommer hela markeringen.
- Finns redan en anteckning med samma namn i valvet får den nya ett nummer: *Möte 2*, *Möte 3* …

## Sök i valvet

Öppnar Obsidians sökning med markeringen som sökord, i valvet du senast hade öppet.

## Valv och rubrik

Klippet använder valvet som är öppet i Obsidian och lägger fångad text under rubriken *Fångat* i dagens anteckning. Finns rubriken inte än läggs den till sist i anteckningen. Vill du ha den på ett annat ställe lägger du in `## Fångat` i mallen för dagliga anteckningar.

## Krav

Obsidian på samma Mac. Klippet skriver valvets Markdown-filer direkt, så Obsidian behöver inte vara öppet för att spara i dagens anteckning. Mappar som börjar med punkt, som `.obsidian`, ändras aldrig. Inget skickas från datorn.
