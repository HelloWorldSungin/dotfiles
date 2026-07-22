import { useSyncExternalStore } from "react";

export type CursorWindow = {
  id: "included_usage" | "auto_usage" | "api_usage";
  label: string;
  percentUsed: number;
  resetAt?: string;
};

export type CursorSnapshot = {
  source: "api";
  accountEmail?: string;
  plan?: string;
  windows: CursorWindow[];
  refreshedAt: string;
  stale: boolean;
};

type Result = { ok: true; data: CursorSnapshot } | { ok: false; error: string; sourceTried: string[] };
export type CursorState =
  | { status: "loading" }
  | { status: "ready"; snapshot: CursorSnapshot }
  | { status: "error"; message: string };

let state: CursorState = { status: "loading" };
let listeners: Array<() => void> = [];
let inFlight = false;

function setState(next: CursorState) {
  state = next;
  for (const listener of listeners) listener();
}

export function useCursorQuotaState(): CursorState {
  return useSyncExternalStore(
    (listener) => {
      listeners.push(listener);
      return () => {
        listeners = listeners.filter((item) => item !== listener);
      };
    },
    () => state,
  );
}

export async function refreshCursorQuota(): Promise<void> {
  if (inFlight) return;
  if (!window.babyMenu) {
    setState({ status: "error", message: "Baby Menu bridge unavailable" });
    return;
  }
  inFlight = true;
  try {
    const result = await window.babyMenu.capabilities.invoke<Result>("cursor-quota", "getQuota");
    setState(result.ok ? { status: "ready", snapshot: result.data } : { status: "error", message: result.error });
  } catch (error) {
    setState({ status: "error", message: error instanceof Error ? error.message : "Cursor quota unavailable" });
  } finally {
    inFlight = false;
  }
}
