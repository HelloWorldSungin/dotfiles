import { execFile } from "node:child_process";
import { request as httpRequest } from "node:http";
import { request as httpsRequest } from "node:https";
import type { BabyMenuDatabase, BabyMenuServerContext } from "@babymenu/contracts";

type AntigravityWindow = {
  id: string;
  label: string;
  percentUsed: number;
  resetAt?: string;
};

type AntigravitySnapshot = {
  source: "local";
  accountEmail?: string;
  plan?: string;
  windows: AntigravityWindow[];
  refreshedAt: string;
  stale: boolean;
};

type Result = { ok: true; data: AntigravitySnapshot } | { ok: false; error: string; sourceTried: string[] };
type LanguageServer = { pid: number; csrf: string; extensionPort?: number };

const STATUS_PATH = "/exa.language_server_pb.LanguageServerService/GetUserStatus";
const SNAPSHOT_TABLE = "antigravity_quota_snapshot";

function exec(command: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(command, args, { timeout: 5000, maxBuffer: 2 * 1024 * 1024 }, (error, stdout) => {
      if (error) reject(error);
      else resolve(stdout.toString());
    });
  });
}

function flag(command: string, name: string): string | undefined {
  const match = command.match(new RegExp(`(?:^|\\s)--${name}(?:=|\\s+)([^\\s]+)`));
  return match?.[1];
}

async function discoverServer(): Promise<LanguageServer | undefined> {
  const output = await exec("ps", ["-ax", "-o", "pid=,command="]);
  for (const line of output.split("\n")) {
    if (!/language_server(?:_macos(?:_arm)?)?/i.test(line) || !/antigravity/i.test(line)) continue;
    const match = line.match(/^\s*(\d+)\s+(.+)$/);
    if (!match) continue;
    const csrf = flag(match[2], "csrf_token");
    if (!csrf) continue;
    const portText = flag(match[2], "extension_server_port");
    return {
      pid: Number(match[1]),
      csrf,
      extensionPort: portText && /^\d+$/.test(portText) ? Number(portText) : undefined,
    };
  }
  return undefined;
}

async function listeningPorts(pid: number): Promise<number[]> {
  try {
    const output = await exec("lsof", ["-nP", "-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN"]);
    const ports = new Set<number>();
    for (const line of output.split("\n")) {
      const match = line.match(/(?:127\.0\.0\.1|\[::1\]|\*):(\d+)\s+\(LISTEN\)/);
      if (match) ports.add(Number(match[1]));
    }
    return [...ports];
  } catch {
    return [];
  }
}

function rpc(port: number, csrf: string, secure: boolean): Promise<{ status: number; body?: unknown }> {
  return new Promise((resolve, reject) => {
    const request = (secure ? httpsRequest : httpRequest)(
      {
        hostname: "127.0.0.1",
        port,
        path: STATUS_PATH,
        method: "POST",
        rejectUnauthorized: false,
        timeout: 4000,
        headers: {
          "content-type": "application/json",
          "connect-protocol-version": "1",
          "x-codeium-csrf-token": csrf,
          "content-length": "2",
        },
      },
      (response) => {
        let raw = "";
        response.setEncoding("utf8");
        response.on("data", (chunk) => {
          if (raw.length < 2 * 1024 * 1024) raw += chunk;
        });
        response.on("end", () => {
          let body: unknown;
          try {
            body = JSON.parse(raw);
          } catch {
            body = undefined;
          }
          resolve({ status: response.statusCode ?? 0, body });
        });
      },
    );
    request.on("timeout", () => request.destroy(new Error("timeout")));
    request.on("error", reject);
    request.end("{}");
  });
}

async function fetchStatus(server: LanguageServer): Promise<unknown> {
  const ports = await listeningPorts(server.pid);
  if (server.extensionPort && !ports.includes(server.extensionPort)) ports.push(server.extensionPort);
  for (const port of ports) {
    for (const secure of [true, false]) {
      try {
        const response = await rpc(port, server.csrf, secure);
        if (response.status === 200 && response.body) return response.body;
      } catch {
        // Probe the next protocol/port.
      }
    }
  }
  return undefined;
}

function text(record: Record<string, unknown>, names: string[]): string | undefined {
  for (const name of names) if (typeof record[name] === "string" && record[name]) return record[name] as string;
  return undefined;
}

function parseReset(value: unknown): string | undefined {
  if (typeof value === "string") {
    const date = new Date(value);
    if (!Number.isNaN(date.getTime())) return date.toISOString();
    const seconds = Number(value);
    if (Number.isFinite(seconds)) return new Date(seconds * 1000).toISOString();
  }
  if (typeof value === "number" && Number.isFinite(value)) return new Date(value * 1000).toISOString();
  return undefined;
}

function normalize(body: unknown): AntigravitySnapshot | undefined {
  if (!body || typeof body !== "object") return undefined;
  const root = body as Record<string, unknown>;
  const status =
    root.userStatus && typeof root.userStatus === "object"
      ? (root.userStatus as Record<string, unknown>)
      : root;
  const cascade =
    status.cascadeModelConfigData && typeof status.cascadeModelConfigData === "object"
      ? (status.cascadeModelConfigData as Record<string, unknown>)
      : undefined;
  const configs = Array.isArray(cascade?.clientModelConfigs) ? cascade.clientModelConfigs : [];
  const parsed: AntigravityWindow[] = [];

  for (let index = 0; index < configs.length; index += 1) {
    const item = configs[index];
    if (!item || typeof item !== "object") continue;
    const config = item as Record<string, unknown>;
    const quota = config.quotaInfo && typeof config.quotaInfo === "object"
      ? (config.quotaInfo as Record<string, unknown>)
      : undefined;
    if (!quota || typeof quota.remainingFraction !== "number" || !Number.isFinite(quota.remainingFraction)) continue;
    const label = text(config, ["displayName", "label", "modelName", "model"]) ?? `model ${index + 1}`;
    parsed.push({
      id: text(config, ["model", "modelName", "id"]) ?? String(index),
      label: label.replace(/^models\//, ""),
      percentUsed: Math.min(100, Math.max(0, (1 - quota.remainingFraction) * 100)),
      resetAt: parseReset(quota.resetTime),
    });
  }

  const gemini = parsed.filter((window) => /gemini/i.test(window.label) || /gemini/i.test(window.id));
  const windows = gemini.length > 0 ? gemini : parsed;
  if (windows.length === 0) return undefined;
  return {
    source: "local",
    accountEmail: text(status, ["email", "accountEmail"]),
    plan: text(status, ["planName", "subscriptionPlan", "tier"]),
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

function persist(db: BabyMenuDatabase, snapshot: AntigravitySnapshot) {
  ensureTable(db);
  db.run(
    `INSERT INTO ${SNAPSHOT_TABLE} (id, snapshot, updated_at) VALUES (1, ?, ?)
     ON CONFLICT(id) DO UPDATE SET snapshot = excluded.snapshot, updated_at = excluded.updated_at`,
    [JSON.stringify(snapshot), Date.now()],
  );
}

function cached(db: BabyMenuDatabase): AntigravitySnapshot | undefined {
  ensureTable(db);
  const row = db.get<{ snapshot: string }>(`SELECT snapshot FROM ${SNAPSHOT_TABLE} WHERE id = 1`);
  if (!row) return undefined;
  try {
    return JSON.parse(row.snapshot) as AntigravitySnapshot;
  } catch {
    return undefined;
  }
}

async function getQuota(_input: unknown, context: BabyMenuServerContext): Promise<Result> {
  const sourceTried = ["local-language-server"];
  try {
    const server = await discoverServer();
    if (!server) return { ok: false, error: "Open Antigravity to view quota", sourceTried };
    const body = await fetchStatus(server);
    const snapshot = normalize(body);
    if (!snapshot) throw new Error("Antigravity quota unavailable");
    persist(context.db, snapshot);
    return { ok: true, data: snapshot };
  } catch {
    const last = cached(context.db);
    return last
      ? { ok: true, data: { ...last, stale: true } }
      : { ok: false, error: "Antigravity quota unavailable", sourceTried };
  }
}

export const actions = { getQuota };
