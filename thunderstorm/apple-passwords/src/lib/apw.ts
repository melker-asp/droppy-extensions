import { execFile, spawn } from "node:child_process";
import { closeSync, existsSync, mkdirSync, openSync } from "node:fs";
import { createConnection } from "node:net";
import { homedir } from "node:os";
import { join } from "node:path";

// apw's own status codes (src/const.ts upstream).
export enum ApwStatus {
  Success = 0,
  GenericError = 1,
  InvalidParam = 2,
  NoResults = 3,
  InvalidSession = 9,
  ServerError = 100,
}

export interface Account {
  username: string;
  domain: string;
  title?: string;
  sites?: string[];
  password?: string;
}

export interface OneTimeCode {
  username: string;
  domain: string;
  source?: string;
  code?: string;
}

export class ApwError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}

/** Thrown when there is no apw binary to run. */
export class ApwMissingError extends Error {}

const DATA_DIR = join(homedir(), ".apw");
const SOCKET = join(DATA_DIR, "apw.sock");
const CANDIDATES = [join(homedir(), ".local/bin/apw"), "/opt/homebrew/bin/apw", "/usr/local/bin/apw"];

export function apwPath(): string {
  const found = CANDIDATES.find((path) => existsSync(path));
  if (!found) throw new ApwMissingError("apw finns inte på den här Macen.");
  return found;
}

function run(args: string[], input?: string): Promise<{ results: unknown[] }> {
  return new Promise((resolve, reject) => {
    const child = execFile(apwPath(), args, { timeout: 35_000 }, (error, stdout, stderr) => {
      // apw prints {results, status} on stdout, or {error, status} on stderr and exits with the status.
      const text = (error ? stderr || stdout : stdout).trim();
      let parsed: { results?: unknown[]; status?: number; error?: string } = {};
      try {
        parsed = JSON.parse(text.split("\n").pop() || "{}");
      } catch {
        // Not JSON: a crash or a timeout.
      }
      if (error || (parsed.status ?? 0) !== ApwStatus.Success) {
        const status = parsed.status ?? ApwStatus.GenericError;
        reject(new ApwError(status, parsed.error || (error?.killed ? "apw svarade inte i tid." : text || String(error))));
        return;
      }
      resolve({ results: parsed.results ?? [] });
    });
    if (input !== undefined) {
      child.stdin?.end(input);
    }
  });
}

/** Turns "https://www.example.com/login" or "Example.com" into "www.example.com" / "example.com". */
export function normalizeDomain(input: string): string {
  const text = input.trim().toLowerCase();
  if (!text) return "";
  try {
    return new URL(text.includes("://") ? text : `https://${text}`).hostname;
  } catch {
    return text;
  }
}

async function list<T>(args: string[]): Promise<T[]> {
  try {
    return (await run(args)).results as T[];
  } catch (error) {
    if (error instanceof ApwError && error.status === ApwStatus.NoResults) return [];
    throw error;
  }
}

export function listAccounts(domain: string): Promise<Account[]> {
  return list<Account>(["pw", "list", domain]);
}

export async function getPassword(domain: string, username: string): Promise<string> {
  const accounts = await list<Account>(["pw", "get", domain, username]);
  const match = accounts.find((account) => account.username === username && account.password) ?? accounts[0];
  if (!match?.password) throw new ApwError(ApwStatus.NoResults, `Hittade inget lösenord för ${username}.`);
  return match.password;
}

export function getOneTimeCodes(domain: string): Promise<OneTimeCode[]> {
  return list<OneTimeCode>(["otp", "get", domain]);
}

export async function savePassword(domain: string, username: string, password: string): Promise<void> {
  // The password goes over stdin so it never shows up in a process list.
  await run(["pw", "save", "--stdin", domain, username], password);
}

/** Asks the daemon for a pairing PIN; macOS shows it in a dialog. */
export async function requestPairing(): Promise<void> {
  await run(["auth", "request"]);
}

export async function confirmPairing(pin: string): Promise<void> {
  await run(["auth", "response", "--pin", pin]);
}

export function isDaemonRunning(): Promise<boolean> {
  return new Promise((resolve) => {
    if (!existsSync(SOCKET)) return resolve(false);
    const socket = createConnection(SOCKET);
    socket.once("connect", () => {
      socket.destroy();
      resolve(true);
    });
    socket.once("error", () => resolve(false));
  });
}

let starting: Promise<void> | undefined;

/** Starts the daemon in the background, once even if several views ask at the same time. */
export function startDaemon(): Promise<void> {
  starting ??= launchDaemon().finally(() => (starting = undefined));
  return starting;
}

async function launchDaemon(): Promise<void> {
  // Detached, so apw keeps running after Thunderstorm closes the command. It
  // starts the browser saved in ~/.apw/config.json (comet).
  mkdirSync(DATA_DIR, { recursive: true, mode: 0o700 });
  const log = openSync(join(DATA_DIR, "apw.log"), "a");
  spawn(apwPath(), ["start"], { detached: true, stdio: ["ignore", log, log] }).unref();
  closeSync(log);
  for (let attempt = 0; attempt < 40; attempt++) {
    if (await isDaemonRunning()) return;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new ApwError(ApwStatus.GenericError, "apw startade inte. Se ~/.apw/apw.log för varför.");
}

export function isSessionError(error: unknown): boolean {
  return error instanceof ApwError && error.status === ApwStatus.InvalidSession;
}
