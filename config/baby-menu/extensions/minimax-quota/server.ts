import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import type { BabyMenuDatabase, BabyMenuServerContext } from "@babymenu/contracts";

type QuotaWindow = {
  id: "session" | "weekly";
  label: string;
  percentUsed: number;
  resetAt?: string;
  resetText?: string;
};

type QuotaSnapshot = {
  source: "api";
  windows: QuotaWindow[];
  refreshedAt: string;
  stale: boolean;
};

type QuotaResult =
  | { ok: true; data: QuotaSnapshot }
  | { ok: false; error: string; sourceTried: string[] };

const USAGE_URL = "https://www.minimax.io/v1/token_plan/remains";
const SNAPSHOT_TABLE = "minimax_quota_snapshot";
const REQUEST_TIMEOUT_MS = 8_000;

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" ? (value as Record<string, unknown>) : undefined;
}

function clampPercent(value: number): number {
  return Math.min(100, Math.max(0, value));
}

function resetFields(epochMs: unknown): Pick<QuotaWindow, "resetAt" | "resetText"> {
  if (typeof epochMs !== "number" || !Number.isFinite(epochMs)) return {};
  const date = new Date(epochMs);
  if (Number.isNaN(date.getTime())) return {};
  const resetAt = date.toISOString();
  const resetText = new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
  return { resetAt, resetText };
}

async function keyFromClaudeSettings(): Promise<string | undefined> {
  try {
    const root = asRecord(JSON.parse(await readFile(join(homedir(), ".claude", "settings.json"), "utf8")));
    const env = asRecord(root?.env);
    const baseUrl = typeof env?.ANTHROPIC_BASE_URL === "string" ? env.ANTHROPIC_BASE_URL : "";
    if (!baseUrl.includes("minimax.io") && !baseUrl.includes("minimaxi.com")) return undefined;
    const token = env?.ANTHROPIC_AUTH_TOKEN ?? env?.ANTHROPIC_API_KEY;
    return typeof token === "string" && token ? token : undefined;
  } catch {
    return undefined;
  }
}

// Menu-bar Electron apps do not inherit interactive-shell exports, so fall back to
// reading the named key from an interactive zsh. Never log the returned value.
async function envFromLoginShell(name: string): Promise<string | undefined> {
  if (!/^[A-Z][A-Z0-9_]*$/.test(name)) return undefined;
  return new Promise((resolve) => {
    // Keys are typically exported from ~/.zshrc (interactive). A bare login
    // shell skips that file, so use -i and close stdin so it cannot hang.
    execFile(
      "/bin/zsh",
      ["-i", "-c", `printf %s "\${${name}-}"`],
      {
        timeout: 5000,
        env: { HOME: homedir(), USER: process.env.USER, PATH: process.env.PATH, TERM: "dumb", SHELL: "/bin/zsh" },
        stdio: ["ignore", "pipe", "pipe"],
      },
      (error, stdout) => {
        if (error) {
          resolve(undefined);
          return;
        }
        const value = stdout.toString().trim();
        resolve(value || undefined);
      },
    );
  });
}

async function resolveApiKey(): Promise<string | undefined> {
  const fromProcess = process.env.MINIMAX_API_KEY?.trim();
  if (fromProcess) return fromProcess;

  const fromShell = await envFromLoginShell("MINIMAX_API_KEY");
  if (fromShell) return fromShell;

  const baseUrl = process.env.ANTHROPIC_BASE_URL ?? "";
  if (baseUrl.includes("minimax.io") || baseUrl.includes("minimaxi.com")) {
    const token = process.env.ANTHROPIC_AUTH_TOKEN ?? process.env.ANTHROPIC_API_KEY;
    if (token) return token;
  }
  return keyFromClaudeSettings();
}

function normalizeResponse(body: unknown): QuotaSnapshot | undefined {
  const root = asRecord(body);
  const remains = Array.isArray(root?.model_remains) ? root.model_remains : [];
  const general =
    remains.map(asRecord).find((entry) => entry?.model_name === "general") ??
    remains.map(asRecord).find((entry) => entry !== undefined);
  if (!general) return undefined;

  const sessionRemaining = general.current_interval_remaining_percent;
  const weeklyRemaining = general.current_weekly_remaining_percent;
  if (typeof sessionRemaining !== "number" || typeof weeklyRemaining !== "number") return undefined;

  return {
    source: "api",
    windows: [
      {
        id: "session",
        label: "session · 5 hour",
        percentUsed: clampPercent(100 - sessionRemaining),
        ...resetFields(general.end_time),
      },
      {
        id: "weekly",
        label: "weekly",
        percentUsed: clampPercent(100 - weeklyRemaining),
        ...resetFields(general.weekly_end_time),
      },
    ],
    refreshedAt: new Date().toISOString(),
    stale: false,
  };
}

function ensureTable(db: BabyMenuDatabase) {
  db.exec(
    `CREATE TABLE IF NOT EXISTS ${SNAPSHOT_TABLE} (id INTEGER PRIMARY KEY CHECK (id = 1), snapshot TEXT NOT NULL, updated_at INTEGER NOT NULL)`,
  );
}

function persistSnapshot(db: BabyMenuDatabase, snapshot: QuotaSnapshot) {
  ensureTable(db);
  db.run(
    `INSERT INTO ${SNAPSHOT_TABLE} (id, snapshot, updated_at) VALUES (1, ?, ?)
     ON CONFLICT(id) DO UPDATE SET snapshot = excluded.snapshot, updated_at = excluded.updated_at`,
    [JSON.stringify(snapshot), Date.now()],
  );
}

function readLastSnapshot(db: BabyMenuDatabase): QuotaSnapshot | undefined {
  ensureTable(db);
  const row = db.get<{ snapshot: string }>(`SELECT snapshot FROM ${SNAPSHOT_TABLE} WHERE id = 1`);
  if (!row) return undefined;
  try {
    return JSON.parse(row.snapshot) as QuotaSnapshot;
  } catch {
    return undefined;
  }
}

async function getQuota(_input: unknown, context: BabyMenuServerContext): Promise<QuotaResult> {
  const sourceTried = ["token-plan-api"];
  const apiKey = await resolveApiKey();
  if (!apiKey) return { ok: false, error: "MiniMax API key required", sourceTried };

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(USAGE_URL, {
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      signal: controller.signal,
    });
    if (response.status === 401 || response.status === 403) {
      return { ok: false, error: "MiniMax sign-in required", sourceTried };
    }

    if (response.ok) {
      let body: unknown;
      try {
        body = await response.json();
      } catch {
        body = undefined;
      }
      const snapshot = normalizeResponse(body);
      if (snapshot) {
        persistSnapshot(context.db, snapshot);
        return { ok: true, data: snapshot };
      }
    }

    const last = readLastSnapshot(context.db);
    if (last) return { ok: true, data: { ...last, stale: true } };
    return { ok: false, error: "MiniMax quota unavailable", sourceTried };
  } catch {
    const last = readLastSnapshot(context.db);
    if (last) return { ok: true, data: { ...last, stale: true } };
    return { ok: false, error: "MiniMax quota unavailable", sourceTried };
  } finally {
    clearTimeout(timer);
  }
}

export const actions = {
  getQuota,
};
