import { execFile, spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import type { BabyMenuDatabase, BabyMenuServerContext } from "@babymenu/contracts";

type ClaudeQuotaWindowId = "five_hour" | "seven_day" | "seven_day_sonnet" | "seven_day_opus" | "seven_day_fable" | "extra_usage";

type ClaudeQuotaWindow = {
  id: ClaudeQuotaWindowId;
  label: string;
  percentUsed?: number;
  resetText?: string;
  resetAt?: string;
  spentUsd?: number;
  limitUsd?: number;
};

type ClaudeQuotaSnapshot = {
  source: "oauth" | "cli";
  accountEmail?: string;
  plan?: string;
  windows: ClaudeQuotaWindow[];
  refreshedAt: string;
  stale: boolean;
};

type QuotaResult<T> = { ok: true; data: T } | { ok: false; error: string; sourceTried: string[] };

const KEYCHAIN_SERVICE = "Claude Code-credentials";
const CREDENTIALS_FILE = join(homedir(), ".claude", ".credentials.json");
const USAGE_URL = "https://api.anthropic.com/api/oauth/usage";
const OAUTH_TIMEOUT_MS = 8000;
const CLI_TIMEOUT_MS = 20000;
const SNAPSHOT_TABLE = "claude_code_quota_snapshot";

function augmentedPath(): string {
  const home = homedir();
  const extra = [`${home}/.local/bin`, `${home}/.claude/local`, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"];
  const existing = (process.env.PATH ?? "").split(":").filter(Boolean);
  return Array.from(new Set([...existing, ...extra])).join(":");
}

function clampPercent(value: number): number {
  return Math.min(100, Math.max(0, value));
}

function planLabel(subscriptionType?: string): string | undefined {
  if (!subscriptionType) return undefined;
  const known: Record<string, string> = { pro: "Claude Pro", max: "Claude Max", team: "Claude Team", enterprise: "Claude Enterprise" };
  return known[subscriptionType.toLowerCase()] ?? subscriptionType;
}

function formatResetText(iso?: string): string | undefined {
  if (!iso) return undefined;
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return undefined;
  return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }).format(date);
}

// --- credential resolution --------------------------------------------------

type CredentialCandidate = {
  source: "keychain" | "file";
  accessToken: string;
  expiresAt?: number;
  plan?: string;
};

function parseOauthBlob(raw: string): { accessToken: string; expiresAt?: number; subscriptionType?: string } | undefined {
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch {
    return undefined;
  }
  if (!json || typeof json !== "object") return undefined;
  const root = json as Record<string, unknown>;
  const oauth = (root.claudeAiOauth && typeof root.claudeAiOauth === "object" ? root.claudeAiOauth : root) as Record<
    string,
    unknown
  >;
  const accessToken = oauth.accessToken ?? oauth.access_token;
  if (typeof accessToken !== "string" || !accessToken) return undefined;
  return {
    accessToken,
    expiresAt: typeof oauth.expiresAt === "number" ? oauth.expiresAt : undefined,
    subscriptionType: typeof oauth.subscriptionType === "string" ? oauth.subscriptionType : undefined,
  };
}

async function readKeychainCredential(): Promise<CredentialCandidate | undefined> {
  if (process.platform !== "darwin") return undefined;
  const raw = await new Promise<string | undefined>((resolve) => {
    execFile(
      "security",
      ["find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
      { timeout: 5000 },
      (err, stdout) => resolve(err ? undefined : stdout.toString()),
    );
  });
  if (!raw) return undefined;
  const parsed = parseOauthBlob(raw.trim());
  if (!parsed) return undefined;
  return { source: "keychain", accessToken: parsed.accessToken, expiresAt: parsed.expiresAt, plan: planLabel(parsed.subscriptionType) };
}

async function readFileCredential(): Promise<CredentialCandidate | undefined> {
  let raw: string;
  try {
    raw = await readFile(CREDENTIALS_FILE, "utf8");
  } catch {
    return undefined;
  }
  const parsed = parseOauthBlob(raw);
  if (!parsed) return undefined;
  return { source: "file", accessToken: parsed.accessToken, expiresAt: parsed.expiresAt, plan: planLabel(parsed.subscriptionType) };
}

async function resolveCredentialOrder(): Promise<CredentialCandidate[]> {
  const [keychain, file] = await Promise.all([readKeychainCredential(), readFileCredential()]);
  const now = Date.now();
  const isUsable = (c: CredentialCandidate | undefined): c is CredentialCandidate =>
    !!c && (c.expiresAt === undefined || c.expiresAt > now);

  const ordered: CredentialCandidate[] = [];
  if (process.platform === "darwin" && isUsable(keychain)) ordered.push(keychain);

  const remaining = [keychain, file].filter(isUsable).filter((c) => !ordered.includes(c));
  remaining.sort((a, b) => (b.expiresAt ?? Number.POSITIVE_INFINITY) - (a.expiresAt ?? Number.POSITIVE_INFINITY));
  for (const candidate of remaining) if (!ordered.includes(candidate)) ordered.push(candidate);

  return ordered;
}

// --- OAuth usage API ---------------------------------------------------------

async function fetchOauthUsage(accessToken: string): Promise<{ status: number; body?: unknown }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), OAUTH_TIMEOUT_MS);
  try {
    const res = await fetch(USAGE_URL, {
      headers: { Authorization: `Bearer ${accessToken}`, "anthropic-beta": "oauth-2025-04-20" },
      signal: controller.signal,
    });
    let body: unknown;
    try {
      body = await res.json();
    } catch {
      body = undefined;
    }
    return { status: res.status, body };
  } finally {
    clearTimeout(timer);
  }
}

function isAbortError(err: unknown): boolean {
  return err instanceof Error && err.name === "AbortError";
}

function windowFromField(id: ClaudeQuotaWindowId, label: string, field: unknown): ClaudeQuotaWindow | undefined {
  if (!field || typeof field !== "object") return undefined;
  const record = field as Record<string, unknown>;
  const window: ClaudeQuotaWindow = { id, label };
  if (typeof record.utilization === "number") window.percentUsed = clampPercent(record.utilization);
  if (typeof record.resets_at === "string") {
    window.resetAt = record.resets_at;
    window.resetText = formatResetText(record.resets_at);
  }
  return window.percentUsed !== undefined || window.resetAt ? window : undefined;
}

function normalizeOauthResponse(body: unknown, plan?: string): ClaudeQuotaSnapshot | undefined {
  if (!body || typeof body !== "object") return undefined;
  const record = body as Record<string, unknown>;
  const windows: ClaudeQuotaWindow[] = [];

  const fiveHour = windowFromField("five_hour", "session", record.five_hour);
  if (fiveHour) windows.push(fiveHour);
  const sevenDay = windowFromField("seven_day", "week", record.seven_day);
  if (sevenDay) windows.push(sevenDay);
  const sonnet = windowFromField("seven_day_sonnet", "week · sonnet", record.seven_day_sonnet);
  if (sonnet) windows.push(sonnet);
  const opus = windowFromField("seven_day_opus", "week · opus", record.seven_day_opus);
  if (opus) windows.push(opus);
  const fable = windowFromField("seven_day_fable", "fable week", record.seven_day_fable || record.fable_week);
  if (fable) windows.push(fable);

  const extra = record.extra_usage as Record<string, unknown> | undefined;
  if (extra && extra.is_enabled === true) {
    windows.push({
      id: "extra_usage",
      label: "extra usage",
      percentUsed: typeof extra.utilization === "number" ? clampPercent(extra.utilization) : undefined,
      spentUsd: typeof extra.used_credits === "number" ? extra.used_credits : undefined,
      limitUsd: typeof extra.monthly_limit === "number" ? extra.monthly_limit : undefined,
    });
  }

  if (windows.length === 0) return undefined;
  return { source: "oauth", plan, windows, refreshedAt: new Date().toISOString(), stale: false };
}

// --- CLI /usage probe --------------------------------------------------------

function stripAnsi(input: string): string {
  return input
    .replace(/\x1b\[[0-9;?]*[a-zA-Z]/g, "")
    .replace(/\x1b\][^\x07]*\x07/g, "")
    .replace(/\x1b[()][A-Za-z0-9]/g, "");
}

async function isClaudeCliAvailable(): Promise<boolean> {
  return new Promise((resolve) => {
    execFile("claude", ["--version"], { timeout: 5000, env: { ...process.env, PATH: augmentedPath() } }, (err) =>
      resolve(!err),
    );
  });
}

// Node's "pipe" stdio is backed by a socketpair on macOS, and BSD `script`
// calls tcgetattr on its own stdin to size the pty it allocates - that call
// fails with ENOTSUP on a socket, so `script` cannot be driven from a Node
// child process here. `expect` allocates its own pty internally (not derived
// from its inherited stdin), so it works over a plain pipe. The whole
// trust-prompt/`/usage` handshake is driven inside the Tcl script so Node only
// has to collect stdout and enforce a hard timeout. The TUI sometimes renders
// adjacent words with cursor-positioning escapes instead of a literal space
// (e.g. the trust-prompt menu), so patterns use `.{0,30}` rather than `\s*`
// to tolerate escape bytes between words in the raw (unstripped) stream.
const CLI_PROBE_SCRIPT = `
set timeout 20
log_user 1
spawn claude --allowed-tools ""
set usage_sent 0
set retried 0
expect {
  -nocase -re {trust.{0,30}this.{0,30}folder} { send "\\r"; exp_continue }
  -nocase -re {not.{0,30}authenticated|please.{0,30}(run|use).{0,10}/login|invalid.{0,10}api.{0,10}key|token.{0,20}expired|update.{0,20}required} { }
  -nocase -re {welcome.{0,30}back|Try \\"} {
    if {$usage_sent == 0} {
      set usage_sent 1
      send "/usage\\r"
    }
    exp_continue
  }
  -nocase -re {current.{0,30}week} { }
  timeout {
    if {$usage_sent == 1 && $retried == 0} {
      set retried 1
      send "/usage\\r"
      exp_continue
    }
  }
}
sleep 1
`;

const AUTH_PROMPT_PATTERN =
  /not.{0,30}authenticated|please.{0,30}(run|use).{0,10}\/login|invalid.{0,10}api.{0,10}key|token.{0,20}expired|update.{0,20}required/i;

async function probeCli(): Promise<{ ok: true; raw: string } | { ok: false; error: string }> {
  if (!(await isClaudeCliAvailable())) return { ok: false, error: "claude CLI not found" };

  return new Promise((resolve) => {
    const child = spawn("expect", ["-f", "-"], {
      cwd: homedir(),
      env: { ...process.env, PATH: augmentedPath() },
      stdio: ["pipe", "pipe", "pipe"],
    });

    let buf = "";
    let settled = false;

    const hardTimeout = setTimeout(() => finish(), CLI_TIMEOUT_MS);

    function finish() {
      if (settled) return;
      settled = true;
      clearTimeout(hardTimeout);
      try {
        child.kill("SIGKILL");
      } catch {
        // already exited
      }
      const plain = stripAnsi(buf);
      if (AUTH_PROMPT_PATTERN.test(plain)) {
        resolve({ ok: false, error: "Claude sign-in required" });
        return;
      }
      if (/current.{0,30}session/i.test(plain) && /current.{0,30}week/i.test(plain)) {
        resolve({ ok: true, raw: plain });
        return;
      }
      resolve({ ok: false, error: buf ? "CLI probe timed out" : "CLI exited before usage was captured" });
    }

    child.stdout.on("data", (chunk: Buffer) => {
      buf += chunk.toString("utf8");
    });
    child.on("error", () => finish());
    child.on("exit", () => finish());

    child.stdin.write(CLI_PROBE_SCRIPT);
    child.stdin.end();
  });
}

function sliceBetween(text: string, startRe: RegExp, endRe?: RegExp): string | undefined {
  const startMatch = startRe.exec(text);
  if (!startMatch) return undefined;
  const from = startMatch.index + startMatch[0].length;
  let to = text.length;
  if (endRe) {
    const rest = text.slice(from);
    const endMatch = endRe.exec(rest);
    if (endMatch) to = from + endMatch.index;
  }
  return text.slice(from, to);
}

function parsePercentAndReset(block: string): { percentUsed?: number; resetText?: string } {
  const percentMatch = block.match(/(\d{1,3})\s*%\s*(used|left)/i);
  let percentUsed: number | undefined;
  if (percentMatch) {
    const value = clampPercent(Number(percentMatch[1]));
    percentUsed = percentMatch[2].toLowerCase() === "left" ? clampPercent(100 - value) : value;
  }
  const resetMatch = block.match(/Resets\s*([^+\n]+?)(?:\s{2,}|$)/i);
  const resetText = resetMatch ? resetMatch[1].trim() : undefined;
  return { percentUsed, resetText };
}

function normalizeCliOutput(raw: string): ClaudeQuotaSnapshot | undefined {
  const sessionBlock = sliceBetween(raw, /Current\s*session/i, /Current\s*week/i);
  const weekBlock = sliceBetween(raw, /Current\s*week[^█\n]*/i, /\+\d+%|What(?:'|’)s contributing/i);

  const windows: ClaudeQuotaWindow[] = [];
  if (sessionBlock) {
    const { percentUsed, resetText } = parsePercentAndReset(sessionBlock);
    if (percentUsed !== undefined) windows.push({ id: "five_hour", label: "session", percentUsed, resetText });
  }
  if (weekBlock) {
    const { percentUsed, resetText } = parsePercentAndReset(weekBlock);
    if (percentUsed !== undefined) windows.push({ id: "seven_day", label: "week", percentUsed, resetText });
  }

  // Parse fable week from CLI output if present
  const fableMatch = raw.match(/fable[^█\n]*?(\d{1,3})\s*%\s*(used|left)/i);
  if (fableMatch) {
    const val = clampPercent(Number(fableMatch[1]));
    const percentUsed = fableMatch[2].toLowerCase() === "left" ? clampPercent(100 - val) : val;
    const resetMatch = raw.slice(fableMatch.index).match(/Resets\s*([^+\n]+?)(?:\s{2,}|$)/i);
    const resetText = resetMatch ? resetMatch[1].trim() : undefined;
    windows.push({ id: "seven_day_fable", label: "fable week", percentUsed, resetText });
  }

  if (windows.length === 0) return undefined;

  const planMatch = raw.match(/·\s*(Claude\s+[A-Za-z]+)\s*·/);
  const emailMatch = raw.match(/([\w.+-]+@[\w.-]+\.\w+)['’]s Organization/i);

  return {
    source: "cli",
    plan: planMatch ? planMatch[1].trim() : undefined,
    accountEmail: emailMatch ? emailMatch[1] : undefined,
    windows,
    refreshedAt: new Date().toISOString(),
    stale: false,
  };
}

// --- persistence --------------------------------------------------------------

function ensureTable(db: BabyMenuDatabase) {
  db.exec(
    `CREATE TABLE IF NOT EXISTS ${SNAPSHOT_TABLE} (id INTEGER PRIMARY KEY CHECK (id = 1), snapshot TEXT NOT NULL, updated_at INTEGER NOT NULL)`,
  );
}

function persistSnapshot(db: BabyMenuDatabase, snapshot: ClaudeQuotaSnapshot) {
  ensureTable(db);
  db.run(
    `INSERT INTO ${SNAPSHOT_TABLE} (id, snapshot, updated_at) VALUES (1, ?, ?)
     ON CONFLICT(id) DO UPDATE SET snapshot = excluded.snapshot, updated_at = excluded.updated_at`,
    [JSON.stringify(snapshot), Date.now()],
  );
}

function readLastSnapshot(db: BabyMenuDatabase): ClaudeQuotaSnapshot | undefined {
  ensureTable(db);
  const row = db.get<{ snapshot: string }>(`SELECT snapshot FROM ${SNAPSHOT_TABLE} WHERE id = 1`);
  if (!row) return undefined;
  try {
    return JSON.parse(row.snapshot) as ClaudeQuotaSnapshot;
  } catch {
    return undefined;
  }
}

// --- action -------------------------------------------------------------------

async function getQuota(_input: unknown, context: BabyMenuServerContext): Promise<QuotaResult<ClaudeQuotaSnapshot>> {
  const sourceTried: string[] = [];
  const candidates = await resolveCredentialOrder();
  let sawAuthRejection = false;
  let sawTimeout = false;

  for (const credential of candidates) {
    sourceTried.push(`oauth:${credential.source}`);
    try {
      const { status, body } = await fetchOauthUsage(credential.accessToken);
      if (status === 200) {
        const snapshot = normalizeOauthResponse(body, credential.plan);
        if (snapshot) {
          persistSnapshot(context.db, snapshot);
          return { ok: true, data: snapshot };
        }
      } else if (status === 401 || status === 403) {
        sawAuthRejection = true;
      }
    } catch (err) {
      if (isAbortError(err)) sawTimeout = true;
    }
  }

  sourceTried.push("cli");
  const cliResult = await probeCli();
  if (cliResult.ok) {
    const snapshot = normalizeCliOutput(cliResult.raw);
    if (snapshot) {
      persistSnapshot(context.db, snapshot);
      return { ok: true, data: snapshot };
    }
    return { ok: false, error: "Could not parse Claude usage output", sourceTried };
  }

  if (cliResult.error === "CLI probe timed out" || sawTimeout) {
    const last = readLastSnapshot(context.db);
    if (last) return { ok: true, data: { ...last, stale: true } };
  }

  if (cliResult.error === "Claude sign-in required" || (sawAuthRejection && cliResult.error === "claude CLI not found")) {
    return { ok: false, error: "Claude sign-in required", sourceTried };
  }

  if (candidates.length === 0 && cliResult.error === "claude CLI not found") {
    return { ok: false, error: "Claude quota unavailable", sourceTried };
  }

  return { ok: false, error: cliResult.error ?? "Claude quota unavailable", sourceTried };
}

export const actions = {
  getQuota,
};
