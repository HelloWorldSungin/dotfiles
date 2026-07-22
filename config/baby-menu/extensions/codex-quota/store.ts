import { useSyncExternalStore } from "react";

export type CodexQuotaWindow = {
  id: "weekly";
  label: "weekly";
  percentUsed: number;
  resetText?: string;
  resetAt?: string;
};

export type CodexQuotaSnapshot = {
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

export type CodexQuotaState =
  | { status: "loading" }
  | { status: "ready"; snapshot: CodexQuotaSnapshot }
  | { status: "error"; message: string };

const EXTENSION_ID = "codex-quota";

let state: CodexQuotaState = { status: "loading" };
let listeners: Array<() => void> = [];
let inFlight = false;

function setState(next: CodexQuotaState) {
  state = next;
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void): () => void {
  listeners.push(listener);
  return () => {
    listeners = listeners.filter((candidate) => candidate !== listener);
  };
}

function getSnapshot(): CodexQuotaState {
  return state;
}

export function useCodexQuotaState(): CodexQuotaState {
  return useSyncExternalStore(subscribe, getSnapshot);
}

export async function refreshCodexQuota(): Promise<void> {
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
  } catch (error) {
    setState({
      status: "error",
      message: error instanceof Error ? error.message : "Failed to load Codex quota",
    });
  } finally {
    inFlight = false;
  }
}
