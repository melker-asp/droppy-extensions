import { getFrontmostApplication } from "@raycast/api";
import { runAppleScript } from "@raycast/utils";
import { normalizeDomain } from "./apw";

// Chromium browsers share Chrome's scripting dictionary; Safari names it differently.
const CHROMIUM = new Set([
  "ai.perplexity.comet",
  "com.google.Chrome",
  "com.brave.Browser",
  "com.microsoft.edgemac",
  "company.thebrowser.Browser",
  "org.chromium.Chromium",
  "com.vivaldi.Vivaldi",
  "net.imput.helium",
]);
const SAFARI = new Set(["com.apple.Safari", "com.apple.SafariTechnologyPreview"]);

/** The domain of the tab in front, when the app behind Thunderstorm is a browser. */
export async function frontmostTabDomain(): Promise<string | undefined> {
  try {
    const app = await getFrontmostApplication();
    const id = app.bundleId ?? "";
    let script: string | undefined;
    if (CHROMIUM.has(id)) script = `tell application id "${id}" to get URL of active tab of front window`;
    if (SAFARI.has(id)) script = `tell application id "${id}" to get URL of front document`;
    if (!script) return undefined;
    const url = await runAppleScript(script, { timeout: 3000 });
    if (!/^https?:/i.test(url)) return undefined;
    return normalizeDomain(url);
  } catch {
    return undefined;
  }
}
