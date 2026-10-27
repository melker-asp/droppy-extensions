import { Action, ActionPanel, Clipboard, Form, Icon, popToRoot, showHUD, showToast, Toast } from "@raycast/api";
import { randomInt } from "node:crypto";
import { useEffect, useState } from "react";
import { normalizeDomain, savePassword } from "./lib/apw";
import { frontmostTabDomain } from "./lib/browser";

interface Props {
  domain?: string;
  username?: string;
}

export default function SavePassword(props: Props) {
  const [domain, setDomain] = useState(props.domain ?? "");
  const [username, setUsername] = useState(props.username ?? "");
  const [password, setPassword] = useState("");
  const [errors, setErrors] = useState<{ domain?: string; username?: string; password?: string }>({});

  useEffect(() => {
    if (props.domain) return;
    frontmostTabDomain().then((tab) => tab && setDomain((current) => current || tab));
  }, []);

  const submit = async () => {
    const site = normalizeDomain(domain);
    const next = {
      domain: site ? undefined : "Skriv en webbplats",
      username: username.trim() ? undefined : "Skriv ett användarnamn",
      password: password ? undefined : "Skriv eller generera ett lösenord",
    };
    setErrors(next);
    if (next.domain || next.username || next.password) return;

    const toast = await showToast({ style: Toast.Style.Animated, title: "Sparar…" });
    try {
      await savePassword(site, username.trim(), password);
      await Clipboard.copy(password, { concealed: true });
      toast.style = Toast.Style.Success;
      toast.title = "Sparat i Lösenord";
      toast.message = "Lösenordet är kopierat.";
      await showHUD(`Sparat för ${site}, lösenordet är kopierat`);
      await popToRoot();
    } catch (err) {
      toast.style = Toast.Style.Failure;
      toast.title = "Kunde inte spara";
      toast.message = err instanceof Error ? err.message : String(err);
    }
  };

  return (
    <Form
      navigationTitle={props.username ? "Byt lösenord" : "Spara lösenord"}
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Spara i Lösenord" icon={Icon.SaveDocument} onSubmit={submit} />
          <Action
            title="Generera starkt lösenord"
            icon={Icon.Wand}
            shortcut={{ modifiers: ["cmd"], key: "g" }}
            onAction={() => {
              setPassword(applePassword());
              setErrors((e) => ({ ...e, password: undefined }));
            }}
          />
        </ActionPanel>
      }
    >
      <Form.TextField
        id="domain"
        title="Webbplats"
        placeholder="github.com"
        value={domain}
        error={errors.domain}
        onChange={(value) => {
          setDomain(value);
          setErrors((e) => ({ ...e, domain: undefined }));
        }}
      />
      <Form.TextField
        id="username"
        title="Användarnamn"
        placeholder="namn@example.com"
        value={username}
        error={errors.username}
        onChange={(value) => {
          setUsername(value);
          setErrors((e) => ({ ...e, username: undefined }));
        }}
      />
      <Form.PasswordField
        id="password"
        title="Lösenord"
        placeholder="⌘ G genererar ett starkt"
        value={password}
        error={errors.password}
        onChange={(value) => {
          setPassword(value);
          setErrors((e) => ({ ...e, password: undefined }));
        }}
      />
      <Form.Description text="Finns kontot redan i Lösenord byts lösenordet ut." />
    </Form>
  );
}

/**
 * Apple's format: three groups of six, joined by hyphens, with one digit and
 * one capital letter, such as "dimvej-2cizqa-Qyzqex".
 */
function applePassword(): string {
  const consonants = "bcdfghjkmnpqrstvwxz";
  const vowels = "aeiouy";
  const pick = (from: string) => from[randomInt(from.length)];
  const chars: string[] = [];
  for (let i = 0; i < 18; i++) chars.push(i % 3 === 1 ? pick(vowels) : pick(consonants));
  const digitAt = randomInt(18);
  let upperAt = randomInt(18);
  while (upperAt === digitAt) upperAt = randomInt(18);
  chars[digitAt] = String(randomInt(10));
  chars[upperAt] = chars[upperAt].toUpperCase();
  return [0, 6, 12].map((start) => chars.slice(start, start + 6).join("")).join("-");
}
