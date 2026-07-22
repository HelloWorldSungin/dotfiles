import { execFile } from "node:child_process";
import { createDecipheriv, createHash, pbkdf2Sync } from "node:crypto";
import { access } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import type { BabyMenuDatabase, BabyMenuServerContext } from "@babymenu/contracts";

type GoWindow = {
  id: "rolling" | "weekly" | "monthly";
  label: string;
  percentUsed: number;
  resetAt?: string;
};

type GoSnapshot = {
  source: "dashboard";
  plan: "OpenCode Go";
  windows: GoWindow[];
  refreshedAt: string;
  stale: boolean;
};

type Result = { ok: true; data: GoSnapshot } | { ok: false; error: string; sourceTried: string[] };

const CHROME_COOKIES = join(homedir(), "Library", "Application Support", "Google", "Chrome", "Default", "Cookies");
const SQLITE_CANDIDATES = ["sqlite3", "/usr/bin/sqlite3", "/opt/homebrew/bin/sqlite3", "/usr/local/bin/sqlite3"];
const SNAPSHOT_TABLE = "opencode_go_quota_snapshot";
const TIMEOUT_MS = 10_000;

function run(command: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(command, args, { timeout: 5000, maxBuffer: 2 * 1024 * 1024 }, (error, stdout) => {
      if (error) reject(error);
      else resolve(stdout.toString());
    });
  });
}

async function findSqlite(): Promise<string | undefined> {
  for (const candidate of SQLITE_CANDIDATES) {
    try {
      await run(candidate, ["-version"]);
      return candidate;
    } catch {
      // Continue through known macOS locations.
    }
  }
  return undefined;
}

async function chromeAuthCookie(): Promise<string | undefined> {
  try {
    await access(CHROME_COOKIES);
  } catch {
    return undefined;
  }
  const sqlite = await findSqlite();
  if (!sqlite) return undefined;
  const encryptedHex = (
    await run(sqlite, [
      "-readonly",
      "-cmd",
      ".timeout 1000",
      CHROME_COOKIES,
      "SELECT hex(encrypted_value) FROM cookies WHERE host_key = 'opencode.ai' AND name = 'auth' ORDER BY last_access_utc DESC LIMIT 1;",
    ])
  ).trim();
  if (!encryptedHex) return undefined;

  const password = (
    await run("/usr/bin/security", ["find-generic-password", "-w", "-s", "Chrome Safe Storage"])
  ).trim();
  if (!password) return undefined;

  const encrypted = Buffer.from(encryptedHex, "hex");
  if (encrypted.length <= 3 || encrypted.subarray(0, 3).toString() !== "v10") return undefined;
  const key = pbkdf2Sync(password, "saltysalt", 1003, 16, "sha1");
  const decipher = createDecipheriv("aes-128-cbc", key, Buffer.alloc(16, 0x20));
  let decrypted = Buffer.concat([decipher.update(encrypted.subarray(3)), decipher.final()]);
  const hostDigest = createHash("sha256").update("opencode.ai").digest();
  if (decrypted.length > 32 && decrypted.subarray(0, 32).equals(hostDigest)) decrypted = decrypted.subarray(32);
  const cookie = decrypted.toString("utf8");
  return cookie.startsWith("Fe26.") ? cookie : undefined;
}

async function fetchPage(path: string, cookie: string): Promise<{ status: number; url: string; text: string }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const response = await fetch(`https://opencode.ai${path}`, {
      headers: {
        Accept: "text/html",
        Cookie: `auth=${cookie}`,
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
      },
      redirect: "follow",
      signal: controller.signal,
    });
    return { status: response.status, url: response.url, text: await response.text() };
  } finally {
    clearTimeout(timer);
  }
}

function workspaceId(html: string): string | undefined {
  return html.match(/\bwrk_[A-Z0-9]+\b/)?.[0];
}

function parseWindow(
  html: string,
  field: string,
  id: GoWindow["id"],
  label: string,
): GoWindow | undefined {
  // The hydration payload can mention a field in a reference table before its
  // populated object. Parse every occurrence and use the concrete candidate
  // with the longest reset window.
  const candidates: Array<{ percent: number; resetSeconds?: number }> = [];
  let start = 0;
  while ((start = html.indexOf(field, start)) >= 0) {
    const block = html.slice(start, start + 1200);
    const percent = Number(block.match(/["']?usagePercent["']?\s*:\s*([0-9.]+)/)?.[1]);
    const resetSeconds = Number(block.match(/["']?resetInSec["']?\s*:\s*([0-9.]+)/)?.[1]);
    if (Number.isFinite(percent)) {
      candidates.push({ percent, resetSeconds: Number.isFinite(resetSeconds) ? resetSeconds : undefined });
    }
    start += field.length;
  }
  const selected = candidates.sort((a, b) => (b.resetSeconds ?? -1) - (a.resetSeconds ?? -1))[0];
  if (!selected) return undefined;
  return {
    id,
    label,
    percentUsed: Math.min(100, Math.max(0, selected.percent)),
    resetAt: selected.resetSeconds !== undefined
      ? new Date(Date.now() + selected.resetSeconds * 1000).toISOString()
      : undefined,
  };
}

function normalize(html: string): GoSnapshot | undefined {
  const windows = [
    parseWindow(html, "rollingUsage", "rolling", "5 hour"),
    parseWindow(html, "weeklyUsage", "weekly", "weekly"),
    parseWindow(html, "monthlyUsage", "monthly", "monthly"),
  ].filter((window): window is GoWindow => !!window);
  if (windows.length === 0) return undefined;
  return {
    source: "dashboard",
    plan: "OpenCode Go",
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

function persist(db: BabyMenuDatabase, snapshot: GoSnapshot) {
  ensureTable(db);
  db.run(
    `INSERT INTO ${SNAPSHOT_TABLE} (id, snapshot, updated_at) VALUES (1, ?, ?)
     ON CONFLICT(id) DO UPDATE SET snapshot = excluded.snapshot, updated_at = excluded.updated_at`,
    [JSON.stringify(snapshot), Date.now()],
  );
}

function cached(db: BabyMenuDatabase): GoSnapshot | undefined {
  ensureTable(db);
  const row = db.get<{ snapshot: string }>(`SELECT snapshot FROM ${SNAPSHOT_TABLE} WHERE id = 1`);
  if (!row) return undefined;
  try {
    return JSON.parse(row.snapshot) as GoSnapshot;
  } catch {
    return undefined;
  }
}

async function getQuota(_input: unknown, context: BabyMenuServerContext): Promise<Result> {
  const sourceTried = ["chrome-session", "opencode-dashboard"];
  try {
    const cookie = await chromeAuthCookie();
    if (!cookie) return { ok: false, error: "OpenCode sign-in required in Chrome", sourceTried };
    const zen = await fetchPage("/zen", cookie);
    const workspace = workspaceId(zen.text);
    if (zen.status !== 200 || !workspace) {
      return { ok: false, error: "OpenCode Go workspace unavailable", sourceTried };
    }
    const dashboard = await fetchPage(`/workspace/${encodeURIComponent(workspace)}/go`, cookie);
    if (dashboard.status === 401 || dashboard.status === 403 || /sign-in|login/i.test(new URL(dashboard.url).pathname)) {
      return { ok: false, error: "OpenCode sign-in required in Chrome", sourceTried };
    }
    if (dashboard.status !== 200) throw new Error("OpenCode dashboard unavailable");
    const snapshot = normalize(dashboard.text);
    if (!snapshot) throw new Error("OpenCode Go dashboard changed");
    persist(context.db, snapshot);
    return { ok: true, data: snapshot };
  } catch {
    const last = cached(context.db);
    return last
      ? { ok: true, data: { ...last, stale: true } }
      : { ok: false, error: "OpenCode Go quota unavailable", sourceTried };
  }
}

export const actions = { getQuota };
