import { execFile } from "node:child_process";
import { access } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import type { BabyMenuDatabase, BabyMenuServerContext } from "@babymenu/contracts";

type CursorWindow = {
  id: "included_usage" | "auto_usage" | "api_usage";
  label: string;
  percentUsed: number;
  resetAt?: string;
};

type CursorSnapshot = {
  source: "api";
  accountEmail?: string;
  plan?: string;
  windows: CursorWindow[];
  refreshedAt: string;
  stale: boolean;
};

type QuotaResult = { ok: true; data: CursorSnapshot } | { ok: false; error: string; sourceTried: string[] };

const DB_PATH = join(homedir(), "Library", "Application Support", "Cursor", "User", "globalStorage", "state.vscdb");
const SQLITE_CANDIDATES = ["sqlite3", "/usr/bin/sqlite3", "/opt/homebrew/bin/sqlite3", "/usr/local/bin/sqlite3"];
const USAGE_URL = "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage";
const PLAN_URL = "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo";
const SNAPSHOT_TABLE = "cursor_quota_snapshot";
const REQUEST_TIMEOUT_MS = 15_000;

function clamp(value: number): number {
  return Math.min(100, Math.max(0, value));
}

function run(command: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(command, args, { timeout: 4000, maxBuffer: 1024 * 1024 }, (error, stdout, stderr) => {
      if (error) {
        const wrapped = new Error("local Cursor credential read failed");
        (wrapped as Error & { detail?: string }).detail = stderr.toString();
        reject(wrapped);
      } else {
        resolve(stdout.toString());
      }
    });
  });
}

async function findSqlite(): Promise<string | undefined> {
  for (const candidate of SQLITE_CANDIDATES) {
    try {
      await run(candidate, ["-version"]);
      return candidate;
    } catch {
      // Try the next known system location.
    }
  }
  return undefined;
}

type LocalCredential = { token: string; email?: string; plan?: string };

async function readCredential(): Promise<LocalCredential | undefined> {
  try {
    await access(DB_PATH);
  } catch {
    return undefined;
  }
  const sqlite = await findSqlite();
  if (!sqlite) throw new Error("Cursor quota unavailable");
  const query =
    "SELECT key, value FROM ItemTable WHERE key IN " +
    "('cursorAuth/accessToken','cursorAuth/cachedEmail','cursorAuth/stripeMembershipType');";
  const output = await run(sqlite, ["-readonly", "-json", "-cmd", ".timeout 1000", DB_PATH, query]);
  const rows = JSON.parse(output) as Array<{ key?: unknown; value?: unknown }>;
  const values = new Map<string, string>();
  for (const row of rows) {
    if (typeof row.key === "string" && typeof row.value === "string") values.set(row.key, row.value);
  }
  const token = values.get("cursorAuth/accessToken");
  if (!token) return undefined;
  const rawPlan = values.get("cursorAuth/stripeMembershipType");
  return {
    token,
    email: values.get("cursorAuth/cachedEmail"),
    plan: rawPlan ? rawPlan.slice(0, 1).toUpperCase() + rawPlan.slice(1) : undefined,
  };
}

async function post(token: string, url: string): Promise<{ status: number; body?: unknown }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "content-type": "application/json",
        "connect-protocol-version": "1",
      },
      body: "{}",
      signal: controller.signal,
    });
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

function resetAt(value: unknown): string | undefined {
  const milliseconds = typeof value === "string" || typeof value === "number" ? Number(value) : NaN;
  if (!Number.isFinite(milliseconds)) return undefined;
  const date = new Date(milliseconds);
  return Number.isNaN(date.getTime()) ? undefined : date.toISOString();
}

function normalize(usageBody: unknown, credential: LocalCredential, planBody?: unknown): CursorSnapshot | undefined {
  if (!usageBody || typeof usageBody !== "object") return undefined;
  const usage = usageBody as Record<string, unknown>;
  const planUsage =
    usage.planUsage && typeof usage.planUsage === "object" ? (usage.planUsage as Record<string, unknown>) : undefined;
  if (!planUsage) return undefined;

  const end = resetAt(usage.billingCycleEnd);
  const definitions: Array<[CursorWindow["id"], string, unknown]> = [
    ["included_usage", "included usage", planUsage.totalPercentUsed],
    ["auto_usage", "auto usage", planUsage.autoPercentUsed],
    ["api_usage", "API usage", planUsage.apiPercentUsed],
  ];
  const windows = definitions.flatMap(([id, label, value]) =>
    typeof value === "number" && Number.isFinite(value)
      ? [{ id, label, percentUsed: clamp(value), resetAt: end }]
      : [],
  );
  if (windows.length === 0) return undefined;

  let plan = credential.plan;
  if (planBody && typeof planBody === "object") {
    const info = (planBody as Record<string, unknown>).planInfo;
    if (info && typeof info === "object" && typeof (info as Record<string, unknown>).planName === "string") {
      plan = (info as Record<string, string>).planName;
    }
  }
  return {
    source: "api",
    accountEmail: credential.email,
    plan,
    windows,
    refreshedAt: new Date().toISOString(),
    stale: false,
  };
}

function ensureTable(db: BabyMenuDatabase) {
  db.exec(
    `CREATE TABLE IF NOT EXISTS ${SNAPSHOT_TABLE} (id INTEGER PRIMARY KEY CHECK (id = 1), snapshot TEXT NOT NULL, updated_at INTEGER NOT NULL)`,
  );
}

function persist(db: BabyMenuDatabase, snapshot: CursorSnapshot) {
  ensureTable(db);
  db.run(
    `INSERT INTO ${SNAPSHOT_TABLE} (id, snapshot, updated_at) VALUES (1, ?, ?)
     ON CONFLICT(id) DO UPDATE SET snapshot = excluded.snapshot, updated_at = excluded.updated_at`,
    [JSON.stringify(snapshot), Date.now()],
  );
}

function cached(db: BabyMenuDatabase): CursorSnapshot | undefined {
  ensureTable(db);
  const row = db.get<{ snapshot: string }>(`SELECT snapshot FROM ${SNAPSHOT_TABLE} WHERE id = 1`);
  if (!row) return undefined;
  try {
    return JSON.parse(row.snapshot) as CursorSnapshot;
  } catch {
    return undefined;
  }
}

async function getQuota(_input: unknown, context: BabyMenuServerContext): Promise<QuotaResult> {
  const sourceTried = ["local-db"];
  let credential: LocalCredential | undefined;
  try {
    credential = await readCredential();
  } catch {
    const last = cached(context.db);
    return last
      ? { ok: true, data: { ...last, stale: true } }
      : { ok: false, error: "Cursor quota unavailable", sourceTried };
  }
  if (!credential) return { ok: false, error: "Cursor sign-in required", sourceTried };

  sourceTried.push("dashboard-api");
  try {
    const usage = await post(credential.token, USAGE_URL);
    if (usage.status === 401 || usage.status === 403) {
      return { ok: false, error: "Cursor sign-in required", sourceTried };
    }
    if (usage.status < 200 || usage.status >= 300) throw new Error("Cursor API unavailable");
    let planBody: unknown;
    try {
      const plan = await post(credential.token, PLAN_URL);
      if (plan.status >= 200 && plan.status < 300) planBody = plan.body;
    } catch {
      // Plan is optional; usage remains authoritative.
    }
    const snapshot = normalize(usage.body, credential, planBody);
    if (!snapshot) throw new Error("Cursor quota response changed");
    persist(context.db, snapshot);
    return { ok: true, data: snapshot };
  } catch {
    const last = cached(context.db);
    return last
      ? { ok: true, data: { ...last, stale: true } }
      : { ok: false, error: "Cursor quota unavailable", sourceTried };
  }
}

export const actions = { getQuota };
