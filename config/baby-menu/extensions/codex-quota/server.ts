import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import type { BabyMenuDatabase, BabyMenuServerContext } from "@babymenu/contracts";

type CodexQuotaWindow = {
  id: "weekly";
  label: "weekly";
  percentUsed: number;
  resetText?: string;
  resetAt?: string;
};

type CodexQuotaSnapshot = {
  source: "oauth" | "cli-rpc";
  accountEmail?: string;
  plan?: string;
  windows: CodexQuotaWindow[];
  refreshedAt: string;
  stale: boolean;
};

type QuotaResult =
  | { ok: true; data: CodexQuotaSnapshot }
  | { ok: false; error: string; sourceTried: string[] };

type Credential = {
  accessToken: string;
  accountId?: string;
};

type RpcMessage = {
  id?: number;
  result?: unknown;
  error?: { message?: string };
};

type CliProbeResult =
  | { ok: true; account: unknown; rateLimits: unknown }
  | { ok: false; error: string; kind: "auth" | "launch" | "timeout" | "other" };

type CredentialResult =
  | { status: "usable"; credential: Credential }
  | { status: "missing" }
  | { status: "signed-out" };

const USAGE_URL = "https://chatgpt.com/backend-api/wham/usage";
const SNAPSHOT_TABLE = "codex_quota_snapshot";
const OAUTH_TIMEOUT_MS = 8_000;
const RPC_STARTUP_TIMEOUT_MS = 15_000;
const RPC_METHOD_TIMEOUT_MS = 8_000;
const WEEK_SECONDS = 7 * 24 * 60 * 60;

function clampPercent(value: number): number {
  return Math.min(100, Math.max(0, value));
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" ? (value as Record<string, unknown>) : undefined;
}

function formatResetText(iso?: string): string | undefined {
  if (!iso) return undefined;
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return undefined;
  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

function resetFields(epochSeconds: unknown): Pick<CodexQuotaWindow, "resetAt" | "resetText"> {
  if (typeof epochSeconds !== "number" || !Number.isFinite(epochSeconds)) return {};
  const resetAt = new Date(epochSeconds * 1_000).toISOString();
  return { resetAt, resetText: formatResetText(resetAt) };
}

function authPath(): string {
  return join(process.env.CODEX_HOME || join(homedir(), ".codex"), "auth.json");
}

function accountIdFromJwt(token: string): string | undefined {
  const payload = token.split(".")[1];
  if (!payload) return undefined;
  try {
    const decoded = asRecord(JSON.parse(Buffer.from(payload, "base64url").toString("utf8")));
    const auth = asRecord(decoded?.["https://api.openai.com/auth"]);
    return typeof auth?.chatgpt_account_id === "string" ? auth.chatgpt_account_id : undefined;
  } catch {
    return undefined;
  }
}

async function readCredential(): Promise<CredentialResult> {
  let raw: string;
  try {
    raw = await readFile(authPath(), "utf8");
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === "ENOENT"
      ? { status: "missing" }
      : { status: "signed-out" };
  }

  let root: Record<string, unknown> | undefined;
  try {
    root = asRecord(JSON.parse(raw));
  } catch {
    return { status: "signed-out" };
  }
  if (!root) return { status: "signed-out" };

  const apiKey = typeof root.OPENAI_API_KEY === "string" && root.OPENAI_API_KEY ? root.OPENAI_API_KEY : undefined;
  const tokens = asRecord(root.tokens);
  const accessToken =
    apiKey ??
    (typeof tokens?.access_token === "string"
      ? tokens.access_token
      : typeof tokens?.accessToken === "string"
        ? tokens.accessToken
        : undefined);
  if (!accessToken) return { status: "signed-out" };

  const storedAccountId =
    typeof tokens?.account_id === "string"
      ? tokens.account_id
      : typeof tokens?.accountId === "string"
        ? tokens.accountId
        : undefined;
  return {
    status: "usable",
    credential: { accessToken, accountId: storedAccountId ?? accountIdFromJwt(accessToken) },
  };
}

function weeklyWindow(
  candidates: Array<{ value: unknown; durationSeconds?: number; fallbackWeekly?: boolean }>,
  usedKey: "used_percent" | "usedPercent",
  resetKey: "reset_at" | "resetsAt",
): CodexQuotaWindow | undefined {
  const parsed = candidates
    .map(({ value, durationSeconds, fallbackWeekly }) => ({
      record: asRecord(value),
      durationSeconds,
      fallbackWeekly,
    }))
    .filter(({ record }) => typeof record?.[usedKey] === "number");

  const exact = parsed.find(
    ({ durationSeconds }) => durationSeconds !== undefined && Math.abs(durationSeconds - WEEK_SECONDS) < 60,
  );
  const longest = parsed
    .filter(({ durationSeconds }) => durationSeconds !== undefined)
    .sort((a, b) => (b.durationSeconds ?? 0) - (a.durationSeconds ?? 0))[0];
  const selected = exact ?? (longest && (longest.durationSeconds ?? 0) >= 6 * 24 * 60 * 60 ? longest : undefined)
    ?? parsed.find(({ fallbackWeekly }) => fallbackWeekly);
  if (!selected?.record) return undefined;

  return {
    id: "weekly",
    label: "weekly",
    percentUsed: clampPercent(selected.record[usedKey] as number),
    ...resetFields(selected.record[resetKey]),
  };
}

function normalizeOauth(body: unknown): CodexQuotaSnapshot | undefined {
  const root = asRecord(body);
  const rateLimit = asRecord(root?.rate_limit);
  const primary = asRecord(rateLimit?.primary_window);
  const secondary = asRecord(rateLimit?.secondary_window);
  const weekly = weeklyWindow(
    [
      {
        value: primary,
        durationSeconds:
          typeof primary?.limit_window_seconds === "number" ? primary.limit_window_seconds : undefined,
      },
      {
        value: secondary,
        durationSeconds:
          typeof secondary?.limit_window_seconds === "number" ? secondary.limit_window_seconds : undefined,
        fallbackWeekly: true,
      },
    ],
    "used_percent",
    "reset_at",
  );
  if (!weekly) return undefined;

  return {
    source: "oauth",
    accountEmail: typeof root?.email === "string" ? root.email : undefined,
    plan: typeof root?.plan_type === "string" ? root.plan_type : undefined,
    windows: [weekly],
    refreshedAt: new Date().toISOString(),
    stale: false,
  };
}

async function fetchOauthUsage(credential: Credential): Promise<{ status: number; body?: unknown }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), OAUTH_TIMEOUT_MS);
  try {
    const headers: Record<string, string> = {
      Authorization: `Bearer ${credential.accessToken}`,
      Accept: "application/json",
    };
    if (credential.accountId) headers["ChatGPT-Account-Id"] = credential.accountId;
    const response = await fetch(USAGE_URL, { headers, signal: controller.signal });
    let body: unknown;
    try {
      body = await response.json();
    } catch {
      body = undefined;
    }
    return { status: response.status, body };
  } finally {
    clearTimeout(timer);
  }
}

function augmentedPath(): string {
  const home = homedir();
  const extra = [`${home}/.local/bin`, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"];
  return Array.from(new Set([...(process.env.PATH ?? "").split(":").filter(Boolean), ...extra])).join(":");
}

async function probeCli(): Promise<CliProbeResult> {
  return new Promise((resolve) => {
    const child = spawn("codex", ["-s", "read-only", "-a", "untrusted", "app-server"], {
      env: { ...process.env, PATH: augmentedPath() },
      stdio: ["pipe", "pipe", "ignore"],
    });
    let settled = false;
    let buffer = "";
    let account: unknown;
    let rateLimits: unknown;
    let methodTimer: ReturnType<typeof setTimeout> | undefined;

    const startupTimer = setTimeout(
      () => finish({ ok: false, error: "Codex CLI timed out", kind: "timeout" }),
      RPC_STARTUP_TIMEOUT_MS,
    );

    function finish(result: CliProbeResult) {
      if (settled) return;
      settled = true;
      clearTimeout(startupTimer);
      if (methodTimer) clearTimeout(methodTimer);
      try {
        child.kill("SIGKILL");
      } catch {
        // already exited
      }
      resolve(result);
    }

    function send(message: Record<string, unknown>) {
      child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", ...message })}\n`);
    }

    function handle(message: RpcMessage) {
      if (message.id === 1) {
        clearTimeout(startupTimer);
        send({ method: "initialized", params: {} });
        send({ id: 2, method: "account/read", params: {} });
        send({ id: 3, method: "account/rateLimits/read", params: {} });
        methodTimer = setTimeout(
          () => finish({ ok: false, error: "Codex CLI timed out", kind: "timeout" }),
          RPC_METHOD_TIMEOUT_MS,
        );
        return;
      }
      if (message.id !== 2 && message.id !== 3) return;
      if (message.error) {
        const text = message.error.message ?? "Codex CLI request failed";
        const kind = /auth|login|sign.?in/i.test(text) ? "auth" : "other";
        finish({ ok: false, error: text, kind });
        return;
      }
      if (message.id === 2) account = message.result;
      if (message.id === 3) rateLimits = message.result;
      if (account !== undefined && rateLimits !== undefined) finish({ ok: true, account, rateLimits });
    }

    child.on("error", (error: NodeJS.ErrnoException) => {
      const blocked = error.code === "EACCES" || error.code === "EPERM";
      finish({
        ok: false,
        error: blocked ? "Codex CLI could not be launched" : "Codex quota unavailable",
        kind: "launch",
      });
    });
    child.on("exit", () => {
      if (!settled) finish({ ok: false, error: "Codex CLI exited before responding", kind: "other" });
    });
    child.stdout.on("data", (chunk: Buffer) => {
      buffer += chunk.toString("utf8");
      let newline = buffer.indexOf("\n");
      while (newline >= 0) {
        const line = buffer.slice(0, newline);
        buffer = buffer.slice(newline + 1);
        try {
          handle(JSON.parse(line) as RpcMessage);
        } catch {
          // Ignore non-JSON output and unrelated notifications.
        }
        newline = buffer.indexOf("\n");
      }
    });

    send({ id: 1, method: "initialize", params: { clientInfo: { name: "baby-menu", version: "1.0.0" } } });
  });
}

function normalizeCli(accountResponse: unknown, limitsResponse: unknown): CodexQuotaSnapshot | undefined {
  const accountRoot = asRecord(accountResponse);
  const account = asRecord(accountRoot?.account);
  const limitsRoot = asRecord(limitsResponse);
  const rateLimits = asRecord(limitsRoot?.rateLimits);
  const primary = asRecord(rateLimits?.primary);
  const secondary = asRecord(rateLimits?.secondary);
  const weekly = weeklyWindow(
    [
      {
        value: primary,
        durationSeconds:
          typeof primary?.windowDurationMins === "number" ? primary.windowDurationMins * 60 : undefined,
      },
      {
        value: secondary,
        durationSeconds:
          typeof secondary?.windowDurationMins === "number" ? secondary.windowDurationMins * 60 : undefined,
        fallbackWeekly: true,
      },
    ],
    "usedPercent",
    "resetsAt",
  );
  if (!weekly) return undefined;

  return {
    source: "cli-rpc",
    accountEmail: typeof account?.email === "string" ? account.email : undefined,
    plan:
      typeof rateLimits?.planType === "string"
        ? rateLimits.planType
        : typeof account?.planType === "string"
          ? account.planType
          : undefined,
    windows: [weekly],
    refreshedAt: new Date().toISOString(),
    stale: false,
  };
}

function ensureTable(db: BabyMenuDatabase) {
  db.exec(
    `CREATE TABLE IF NOT EXISTS ${SNAPSHOT_TABLE} (id INTEGER PRIMARY KEY CHECK (id = 1), snapshot TEXT NOT NULL, updated_at INTEGER NOT NULL)`,
  );
}

function persistSnapshot(db: BabyMenuDatabase, snapshot: CodexQuotaSnapshot) {
  ensureTable(db);
  db.run(
    `INSERT INTO ${SNAPSHOT_TABLE} (id, snapshot, updated_at) VALUES (1, ?, ?)
     ON CONFLICT(id) DO UPDATE SET snapshot = excluded.snapshot, updated_at = excluded.updated_at`,
    [JSON.stringify(snapshot), Date.now()],
  );
}

function readLastSnapshot(db: BabyMenuDatabase): CodexQuotaSnapshot | undefined {
  ensureTable(db);
  const row = db.get<{ snapshot: string }>(`SELECT snapshot FROM ${SNAPSHOT_TABLE} WHERE id = 1`);
  if (!row) return undefined;
  try {
    return JSON.parse(row.snapshot) as CodexQuotaSnapshot;
  } catch {
    return undefined;
  }
}

async function getQuota(_input: unknown, context: BabyMenuServerContext): Promise<QuotaResult> {
  const sourceTried: string[] = [];
  const credentialResult = await readCredential();
  const credential = credentialResult.status === "usable" ? credentialResult.credential : undefined;

  if (credential) {
    sourceTried.push("oauth");
    try {
      const response = await fetchOauthUsage(credential);
      if (response.status === 200) {
        const snapshot = normalizeOauth(response.body);
        if (snapshot) {
          persistSnapshot(context.db, snapshot);
          return { ok: true, data: snapshot };
        }
      }
    } catch {
      // The CLI can refresh credentials and is the authoritative fallback.
    }
  }

  sourceTried.push("cli-rpc");
  const cli = await probeCli();
  if (cli.ok) {
    const snapshot = normalizeCli(cli.account, cli.rateLimits);
    if (snapshot) {
      persistSnapshot(context.db, snapshot);
      return { ok: true, data: snapshot };
    }
  }

  const last = readLastSnapshot(context.db);
  if (last) return { ok: true, data: { ...last, stale: true } };

  if (credentialResult.status === "signed-out" || (!cli.ok && cli.kind === "auth")) {
    return { ok: false, error: "Codex sign-in required", sourceTried };
  }
  if (!cli.ok && cli.error === "Codex CLI could not be launched") {
    return { ok: false, error: cli.error, sourceTried };
  }
  return { ok: false, error: "Codex quota unavailable", sourceTried };
}

export const actions = {
  getQuota,
};
