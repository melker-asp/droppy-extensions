import { Action, ActionPanel, Clipboard, Icon, List, showHUD, showToast, Toast } from "@raycast/api";
import { Account, getOneTimeCodes, getPassword, listAccounts } from "./lib/apw";
import { deliver, primaryDelivery, ProblemView, useDomainLookup } from "./lib/shared";
import SavePassword from "./save-password";

export default function SearchPasswords() {
  const lookup = useDomainLookup(listAccounts);
  const primary = primaryDelivery();

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
      ) : !lookup.domain ? (
        <List.EmptyView
          icon={Icon.Key}
          title="Skriv en webbplats"
          description="Kontona för den visas här. Är en webbläsare framme fylls dess flik i åt dig."
        />
      ) : (
        <List.EmptyView
          icon={Icon.Key}
          title={`Inga konton för ${lookup.domain}`}
          description="Spara ett med ⌘ N."
          actions={
            <ActionPanel>
              <Action.Push
                title="Spara lösenord"
                icon={Icon.Plus}
                shortcut={{ modifiers: ["cmd"], key: "n" }}
                target={<SavePassword domain={lookup.domain} />}
              />
            </ActionPanel>
          }
        />
      )}
      {lookup.items.map((account) => (
        <AccountItem key={`${account.domain}:${account.username}`} account={account} primary={primary} />
      ))}
    </List>
  );
}

function AccountItem({ account, primary }: { account: Account; primary: "paste" | "copy" }) {
  const secondary = primary === "paste" ? "copy" : "paste";
  const sites = account.sites?.length ? account.sites : [account.domain];

  const withPassword = async (how: "paste" | "copy") => {
    const toast = await showToast({ style: Toast.Style.Animated, title: "Hämtar lösenordet…" });
    try {
      const password = await getPassword(account.domain, account.username);
      await toast.hide();
      await deliver(password, how, "Lösenordet");
    } catch (err) {
      toast.style = Toast.Style.Failure;
      toast.title = "Kunde inte hämta lösenordet";
      toast.message = err instanceof Error ? err.message : String(err);
    }
  };

  const withCode = async () => {
    const toast = await showToast({ style: Toast.Style.Animated, title: "Hämtar koden…" });
    try {
      const codes = await getOneTimeCodes(account.domain);
      const code = (codes.find((c) => c.username === account.username) ?? codes[0])?.code;
      if (!code) throw new Error(`${account.domain} har ingen engångskod i Lösenord.`);
      await toast.hide();
      await deliver(code, primary, "Koden");
    } catch (err) {
      toast.style = Toast.Style.Failure;
      toast.title = "Ingen engångskod";
      toast.message = err instanceof Error ? err.message : String(err);
    }
  };

  return (
    <List.Item
      icon={Icon.Key}
      title={account.username || "Utan användarnamn"}
      subtitle={account.title ?? account.domain}
      accessories={sites.length > 1 ? [{ text: `${sites.length} webbplatser`, tooltip: sites.join("\n") }] : []}
      keywords={sites}
      actions={
        <ActionPanel>
          <ActionPanel.Section>
            <Action
              title={primary === "paste" ? "Klistra in lösenordet" : "Kopiera lösenordet"}
              icon={primary === "paste" ? Icon.Text : Icon.Clipboard}
              onAction={() => withPassword(primary)}
            />
            <Action
              title={secondary === "paste" ? "Klistra in lösenordet" : "Kopiera lösenordet"}
              icon={secondary === "paste" ? Icon.Text : Icon.Clipboard}
              shortcut={{ modifiers: ["cmd"], key: "return" }}
              onAction={() => withPassword(secondary)}
            />
            <Action
              title="Kopiera användarnamnet"
              icon={Icon.Person}
              shortcut={{ modifiers: ["cmd", "shift"], key: "c" }}
              onAction={async () => {
                await Clipboard.copy(account.username);
                await showHUD("Användarnamnet kopierat");
              }}
            />
            <Action
              title="Engångskod"
              icon={Icon.Clock}
              shortcut={{ modifiers: ["cmd"], key: "t" }}
              onAction={withCode}
            />
          </ActionPanel.Section>
          <ActionPanel.Section>
            <Action.OpenInBrowser
              title="Öppna webbplatsen"
              url={`https://${account.domain}`}
              shortcut={{ modifiers: ["cmd"], key: "o" }}
            />
            <Action.Push
              title="Byt lösenord"
              icon={Icon.Pencil}
              shortcut={{ modifiers: ["cmd"], key: "e" }}
              target={<SavePassword domain={account.domain} username={account.username} />}
            />
          </ActionPanel.Section>
        </ActionPanel>
      }
    />
  );
}
