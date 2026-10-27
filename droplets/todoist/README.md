# Todoist

Dagens Todoist-uppgifter på Droppys hylla.

- **Lista**: idag och försenat (eller bara idag, eller närmaste 7 dagarna). Klicka på cirkeln för att bocka av, på raden för att öppna uppgiften i Todoist. Ångra syns några sekunder efteråt.
- **Snabbtillägg**: skriv i fältet överst som i Todoist, "Läs kap 4 fredag #Skola p1", och tryck Retur.
- **Påminnelse**: innan en uppgift med klockslag visas nedräkningen bredvid notchen, och ett kort på notchen när påminnelsen börjar. Välj hur långt innan i inställningarna.
- **Från andra appar**: Todoist-clipet i DropClip gör markerad text till en uppgift, med länk tillbaka till källan.

## Anslut

Öppna dropletens sida i Droppys inställningar och klistra in din API-token från Todoist (Inställningar, Integrationer, Utvecklare). Den sparas i nyckelringen och skickas bara till api.todoist.com.

## Länkar

`droppy://droplet/todoist/add?text=…` lägger till en uppgift. `mode=edit` (standard) öppnar hyllan med texten i fältet, `mode=quick` lägger till med snabbtilläggets tolkning, `mode=plain&due=today` lägger till texten som den är. `note=` blir uppgiftens beskrivning. Länkar kan bara lägga till och kan stängas av i inställningarna.
