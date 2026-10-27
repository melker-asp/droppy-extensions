import { Action, ActionPanel, Icon, List } from "@raycast/api";
import { getOneTimeCodes } from "./lib/apw";
import { deliver, primaryDelivery, ProblemView, useDomainLookup } from "./lib/shared";

export default function OneTimeCodes() {
  const lookup = useDomainLookup(getOneTimeCodes);
  const primary = primaryDelivery();
  const secondary = primary === "paste" ? "copy" : "paste";

  return (
    <List
      isLoading={lookup.isLoading}
      searchText={lookup.searchText}
      onSearchTextChange={lookup.setSearchText}
      searchBarPlaceholder="Webbplats, till exempel github.com"
      filtering={false}
      throttle
    >
      {lookup.error ? (
        <ProblemView error={lookup.error} onFixed={lookup.retry} />
      ) : (
        <List.EmptyView
          icon={Icon.Clock}
          title={lookup.domain ? `Ingen engångskod för ${lookup.domain}` : "Skriv en webbplats"}
          description={
            lookup.domain
              ? "Lägg till en verifieringskod för kontot i appen Lösenord."
              : "Koden för den visas här. Är en webbläsare framme fylls dess flik i åt dig."
          }
        />
      )}
      {lookup.items.map((otp, index) => (
        <List.Item
          key={`${otp.domain}:${otp.username}:${index}`}
          icon={Icon.Clock}
          title={formatCode(otp.code)}
          subtitle={otp.username}
          accessories={[{ text: otp.domain }]}
          actions={
            otp.code ? (
              <ActionPanel>
                <Action
                  title={primary === "paste" ? "Klistra in koden" : "Kopiera koden"}
                  icon={primary === "paste" ? Icon.Text : Icon.Clipboard}
                  onAction={() => deliver(otp.code!, primary, "Koden")}
                />
                <Action
                  title={secondary === "paste" ? "Klistra in koden" : "Kopiera koden"}
                  icon={secondary === "paste" ? Icon.Text : Icon.Clipboard}
                  shortcut={{ modifiers: ["cmd"], key: "return" }}
                  onAction={() => deliver(otp.code!, secondary, "Koden")}
                />
                <Action
                  title="Hämta en ny kod"
                  icon={Icon.ArrowClockwise}
                  shortcut={{ modifiers: ["cmd"], key: "r" }}
                  onAction={lookup.retry}
                />
              </ActionPanel>
            ) : undefined
          }
        />
      ))}
    </List>
  );
}

/** "123456" reads as "123 456", the way Apple shows codes. */
function formatCode(code?: string): string {
  if (!code) return "Ingen kod";
  return code.length === 6 ? `${code.slice(0, 3)} ${code.slice(3)}` : code;
}
