import { useSyncExternalStore } from "react";

export type AntigravityWindow = { id: string; label: string; percentUsed: number; resetAt?: string };
export type AntigravitySnapshot = {
  source: "local";
  accountEmail?: string;
  plan?: string;
  windows: AntigravityWindow[];
  refreshedAt: string;
  stale: boolean;
};

type Result =
  | { ok: true; data: AntigravitySnapshot }
  | { ok: false; error: string; sourceTried: string[] };
export type AntigravityState =
  | { status: "loading" }
  | { status: "ready"; snapshot: AntigravitySnapshot }
  | { status: "error"; message: string };

let state: AntigravityState = { status: "loading" };
let listeners: Array<() => void> = [];
let inFlight = false;

function setState(next: AntigravityState) {
  state = next;
  for (const listener of listeners) listener();
}

export function useAntigravityState(): AntigravityState {
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

export async function refreshAntigravityQuota(): Promise<void> {
  if (inFlight) return;
  if (!window.babyMenu) {
    setState({ status: "error", message: "Baby Menu bridge unavailable" });
    return;
  }
  inFlight = true;
  try {
    const result = await window.babyMenu.capabilities.invoke<Result>("antigravity-quota", "getQuota");
    setState(result.ok ? { status: "ready", snapshot: result.data } : { status: "error", message: result.error });
  } catch (error) {
    setState({ status: "error", message: error instanceof Error ? error.message : "Antigravity quota unavailable" });
  } finally {
    inFlight = false;
  }
}
