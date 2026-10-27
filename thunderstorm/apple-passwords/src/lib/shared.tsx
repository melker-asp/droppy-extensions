import {
  Action,
  ActionPanel,
  Clipboard,
  closeMainWindow,
  Form,
  getPreferenceValues,
  Icon,
  List,
  showHUD,
  showToast,
  Toast,
  useNavigation,
} from "@raycast/api";
import { useEffect, useRef, useState } from "react";
import {
  ApwMissingError,
  confirmPairing,
  isDaemonRunning,
  isSessionError,
  normalizeDomain,
  requestPairing,
  startDaemon,
} from "./apw";
import { frontmostTabDomain } from "./browser";

type Delivery = "paste" | "copy";

export function primaryDelivery(): Delivery {
  return getPreferenceValues<{ primaryAction?: Delivery }>().primaryAction ?? "paste";
}

/** Pastes into the app in front, or copies, without the secret lingering in clipboard history. */
export async function deliver(secret: string, how: Delivery, what: string) {
  if (how === "paste") {
    await Clipboard.copy(secret, { concealed: true });
    await closeMainWindow();
    await Clipboard.paste(secret);
  } else {
    await Clipboard.copy(secret, { concealed: true });
    await showHUD(`${what} kopierat`);
  }
}

/**
 * Search text that starts as the front browser tab's domain and is looked up
 * once typing pauses. `load` runs for every settled domain.
 */
export function useDomainLookup<T>(load: (domain: string) => Promise<T[]>) {
  const [searchText, setSearchText] = useState("");
  const [domain, setDomain] = useState("");
  const [items, setItems] = useState<T[]>([]);
  const [error, setError] = useState<unknown>();
  const [isLoading, setIsLoading] = useState(true);
  const [reload, setReload] = useState(0);
  const run = useRef(0);

  useEffect(() => {
    frontmostTabDomain().then((tab) => {
      if (tab) {
        setSearchText(tab);
        setDomain(tab);
      } else {
        setIsLoading(false);
      }
    });
  }, []);

  useEffect(() => {
    const timer = setTimeout(() => setDomain(normalizeDomain(searchText)), 350);
    return () => clearTimeout(timer);
  }, [searchText]);

  useEffect(() => {
    if (!domain) {
      setItems([]);
      return;
    }
    const id = ++run.current;
    setIsLoading(true);
    load(domain)
      .then((result) => {
        if (id !== run.current) return;
        setItems(result);
        setError(undefined);
      })
      .catch((err) => {
        if (id !== run.current) return;
        setItems([]);
        setError(err);
      })
      .finally(() => {
        if (id === run.current) setIsLoading(false);
      });
  }, [domain, reload]);

  return {
    searchText,
    setSearchText,
    domain,
    items,
    error,
    isLoading,
    retry: () => setReload((n) => n + 1),
  };
}

/** What to show when apw cannot answer: missing, not running, not paired, or another error. */
export function ProblemView({ error, onFixed }: { error: unknown; onFixed: () => void }) {
  const [running, setRunning] = useState<boolean>();
  const [startError, setStartError] = useState<string>();
  useEffect(() => {
    if (!isSessionError(error)) return;
    // Not running: start apw on its own, then look up again (and land on Anslut).
    isDaemonRunning().then(async (isRunning) => {
      setRunning(isRunning);
      if (isRunning) return;
      try {
        await startDaemon();
        onFixed();
      } catch (err) {
        setStartError(err instanceof Error ? err.message : String(err));
      }
    });
  }, [error]);

  if (error instanceof ApwMissingError) {
    return (
      <List.EmptyView
        icon={Icon.Warning}
        title="apw är inte installerat"
        description="Tillägget hämtar lösenorden genom apw. Lägg apw i ~/.local/bin eller installera det med Homebrew."
      />
    );
  }

  if (isSessionError(error) && running !== true) {
    if (!startError) {
      return <List.EmptyView icon={Icon.Power} title="Startar apw…" description="Det tar några sekunder." />;
    }
    return (
      <List.EmptyView
        icon={Icon.Power}
        title="apw startade inte"
        description={startError}
        actions={
          <ActionPanel>
            <Action
              title="Starta apw"
              icon={Icon.Play}
              onAction={async () => {
                const toast = await showToast({ style: Toast.Style.Animated, title: "Startar apw…" });
                try {
                  await startDaemon();
                  toast.style = Toast.Style.Success;
                  toast.title = "apw är igång";
                  onFixed();
                } catch (err) {
                  toast.style = Toast.Style.Failure;
                  toast.title = "Kunde inte starta apw";
                  toast.message = err instanceof Error ? err.message : String(err);
                }
              }}
            />
          </ActionPanel>
        }
      />
    );
  }

  if (isSessionError(error)) {
    return (
      <List.EmptyView
        icon={Icon.Lock}
        title="Anslut till Lösenord"
        description="apw behöver anslutas varje gång det startar. Tryck Retur, så visar macOS en kod som du skriver in här."
        actions={
          <ActionPanel>
            <Action.Push title="Anslut" icon={Icon.Link} target={<PairForm onPaired={onFixed} />} />
          </ActionPanel>
        }
      />
    );
  }

  return (
    <List.EmptyView
      icon={Icon.ExclamationMark}
      title="Lösenord svarade inte"
      description={error instanceof Error ? error.message : String(error)}
      actions={
        <ActionPanel>
          <Action title="Försök igen" icon={Icon.ArrowClockwise} onAction={onFixed} />
        </ActionPanel>
      }
    />
  );
}

function PairForm({ onPaired }: { onPaired: () => void }) {
  const { pop } = useNavigation();
  const [pinError, setPinError] = useState<string>();

  const ask = async () => {
    try {
      await requestPairing();
    } catch (err) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Kunde inte be om en kod",
        message: err instanceof Error ? err.message : String(err),
      });
    }
  };

  useEffect(() => {
    ask();
  }, []);

  return (
    <Form
      navigationTitle="Anslut till Lösenord"
      actions={
        <ActionPanel>
          <Action.SubmitForm
            title="Anslut"
            icon={Icon.Link}
            onSubmit={async (values: { pin: string }) => {
              const pin = values.pin.replace(/\D/g, "");
              if (pin.length !== 6) {
                setPinError("Koden har sex siffror");
                return;
              }
              const toast = await showToast({ style: Toast.Style.Animated, title: "Ansluter…" });
              try {
                await confirmPairing(pin);
                toast.style = Toast.Style.Success;
                toast.title = "Ansluten till Lösenord";
                pop();
                onPaired();
              } catch (err) {
                toast.style = Toast.Style.Failure;
                toast.title = "Koden stämde inte";
                toast.message = "Be om en ny kod och försök igen.";
              }
            }}
          />
          <Action
            title="Be om en ny kod"
            icon={Icon.ArrowClockwise}
            shortcut={{ modifiers: ["cmd"], key: "r" }}
            onAction={ask}
          />
        </ActionPanel>
      }
    >
      <Form.Description text="macOS visar en kod med sex siffror. Skriv in den här." />
      <Form.TextField
        id="pin"
        title="Kod"
        placeholder="123456"
        error={pinError}
        onChange={() => setPinError(undefined)}
      />
    </Form>
  );
}
