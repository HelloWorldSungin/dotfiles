import { useSyncExternalStore } from "react";

export type QuotaWindow = {
  id: "session" | "weekly";
  label: string;
  percentUsed: number;
  resetAt?: string;
  resetText?: string;
};

type QuotaSnapshot = {
  source: "api";
  plan?: string;
  windows: QuotaWindow[];
  refreshedAt: string;
  stale: boolean;
};

type QuotaResult =
  | { ok: true; data: QuotaSnapshot }
  | { ok: false; error: string; sourceTried: string[] };

export type QuotaState =
  | { status: "loading" }
  | { status: "ready"; snapshot: QuotaSnapshot }
  | { status: "error"; message: string };

const EXTENSION_ID = "zai-quota";

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
    listeners = listeners.filter((candidate) => candidate !== listener);
  };
}

function getSnapshot(): QuotaState {
  return state;
}

export function useZaiQuotaState(): QuotaState {
  return useSyncExternalStore(subscribe, getSnapshot);
}

export async function refreshZaiQuota(): Promise<void> {
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
      message: error instanceof Error ? error.message : "Failed to load Z.AI quota",
    });
  } finally {
    inFlight = false;
  }
}
