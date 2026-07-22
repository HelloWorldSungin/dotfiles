import { useSyncExternalStore } from "react";

export type GoWindow = {
  id: "rolling" | "weekly" | "monthly";
  label: string;
  percentUsed: number;
  resetAt?: string;
};
export type GoSnapshot = {
  source: "dashboard";
  plan: "OpenCode Go";
  windows: GoWindow[];
  refreshedAt: string;
  stale: boolean;
};

type Result = { ok: true; data: GoSnapshot } | { ok: false; error: string; sourceTried: string[] };
export type GoState =
  | { status: "loading" }
  | { status: "ready"; snapshot: GoSnapshot }
  | { status: "error"; message: string };

let state: GoState = { status: "loading" };
let listeners: Array<() => void> = [];
let inFlight = false;

function setState(next: GoState) {
  state = next;
  for (const listener of listeners) listener();
}

export function useGoQuotaState(): GoState {
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

export async function refreshGoQuota(): Promise<void> {
  if (inFlight) return;
  if (!window.babyMenu) {
    setState({ status: "error", message: "Baby Menu bridge unavailable" });
    return;
  }
  inFlight = true;
  try {
    const result = await window.babyMenu.capabilities.invoke<Result>("opencode-go-quota", "getQuota");
    setState(result.ok ? { status: "ready", snapshot: result.data } : { status: "error", message: result.error });
  } catch (error) {
    setState({ status: "error", message: error instanceof Error ? error.message : "OpenCode Go quota unavailable" });
  } finally {
    inFlight = false;
  }
}
