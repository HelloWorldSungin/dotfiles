import { useSyncExternalStore } from "react";

export type ClaudeQuotaWindow = {
  id: "five_hour" | "seven_day" | "seven_day_sonnet" | "seven_day_opus" | "seven_day_fable" | "extra_usage";
  label: string;
  percentUsed?: number;
  resetText?: string;
  resetAt?: string;
  spentUsd?: number;
  limitUsd?: number;
};

export type ClaudeQuotaSnapshot = {
  source: "oauth" | "cli";
  accountEmail?: string;
  plan?: string;
  windows: ClaudeQuotaWindow[];
  refreshedAt: string;
  stale: boolean;
};

type QuotaResult =
  | { ok: true; data: ClaudeQuotaSnapshot }
  | { ok: false; error: string; sourceTried: string[] };

export type QuotaState =
  | { status: "loading" }
  | { status: "ready"; snapshot: ClaudeQuotaSnapshot }
  | { status: "error"; message: string };

const EXTENSION_ID = "claude-code-quota";

let state: QuotaState = { status: "loading" };
let listeners: Array<() => void> = [];
let inFlight = false;

function setState(next: QuotaState) {
  state = next;
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void): () => void {
  listeners.push(listener);
  return () => {
    listeners = listeners.filter((l) => l !== listener);
  };
}

function getSnapshot(): QuotaState {
  return state;
}

export function useClaudeQuotaState(): QuotaState {
  return useSyncExternalStore(subscribe, getSnapshot);
}

export async function refreshClaudeQuota(): Promise<void> {
  if (inFlight) return;
  if (!window.babyMenu) {
    setState({ status: "error", message: "Baby Menu bridge unavailable" });
    return;
  }
  inFlight = true;
  try {
    const result = await window.babyMenu.capabilities.invoke<QuotaResult>(EXTENSION_ID, "getQuota");
    if (result.ok) setState({ status: "ready", snapshot: result.data });
    else setState({ status: "error", message: result.error });
  } catch (err) {
    setState({ status: "error", message: err instanceof Error ? err.message : "Failed to load Claude quota" });
  } finally {
    inFlight = false;
  }
}
