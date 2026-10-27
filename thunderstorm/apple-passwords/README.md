# Lösenord för Thunderstorm

Hämta lösenord och engångskoder från Apples Lösenord direkt i Thunderstorm, och spara nya konton.

- **Sök lösenord**: skriv en webbplats, eller öppna kommandot med en webbläsare framme så fylls fliken i. Retur klistrar in lösenordet i appen framför, ⌘ Retur kopierar det. ⌘ ⇧ C kopierar användarnamnet, ⌘ T hämtar engångskoden, ⌘ E byter lösenord.
- **Engångskoder**: tvåstegskoden för en webbplats, klar att klistra in.
- **Spara lösenord**: lägg till ett konto eller byt lösenordet på ett befintligt. ⌘ G genererar ett starkt lösenord i Apples stil.

I inställningarna väljer du om Retur ska klistra in eller kopiera.

## Så fungerar det

Tillägget kör [apw](https://github.com/bendews/apw). apw startar en osynlig Comet med Apples tillägg iCloud Passwords och pratar med Lösenord genom det. Sedan macOS 26.3 får bara godkända webbläsare starta Apples hjälpprogram, så det går inte utan webbläsare. Comet finns på Apples lista.

apw med Comet-stöd byggs från `../../tools/apw` (se `../../tools/apw-comet.patch`) och ligger i `~/.local/bin/apw`.

Varje gång apw startar behöver det anslutas: tillägget visar **Anslut**, macOS visar en kod med sex siffror och du skriver in den.

## Utveckling

```bash
npm install
npm run typecheck
```

Droppy bygger `src/<kommando>.tsx` med esbuild när mappen läggs till i Thunderstorm (Inställningar, Thunderstorm, Tillägg, Utvecklarläge, Lägg till tilläggsmapp).
