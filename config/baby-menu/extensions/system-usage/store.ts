import { useSyncExternalStore } from "react";

export type SystemUsageSample = {
  cpuPercent?: number;
  gpuPercent?: number;
  ramPercent: number;
  ramUsedBytes: number;
  ramTotalBytes: number;
  diskPercent: number;
  diskUsedBytes: number;
  diskTotalBytes: number;
  sampledAt: string;
};

type SampleResult = { ok: true; data: SystemUsageSample } | { ok: false; error: string };

export type RamApp = {
  name: string;
  memoryBytes: number;
  iconDataUrl?: string;
};

type RamAppsResult = { ok: true; data: { apps: RamApp[]; sampledAt: string } } | { ok: false; error: string };

export type RamAppsState =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "ready"; apps: RamApp[] }
  | { status: "error"; message: string };

export type UsageState =
  | { status: "loading" }
  | { status: "ready"; sample: SystemUsageSample; stale: boolean }
  | { status: "error"; message: string };

const EXTENSION_ID = "system-usage";

let state: UsageState = { status: "loading" };
let listeners: Array<() => void> = [];
let inFlight = false;

function setState(next: UsageState) {
  state = next;
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void): () => void {
  listeners.push(listener);
  return () => {
    listeners = listeners.filter((l) => l !== listener);
  };
}

function getSnapshot(): UsageState {
  return state;
}

export function useSystemUsageState(): UsageState {
  return useSyncExternalStore(subscribe, getSnapshot);
}

export async function refreshSystemUsage(): Promise<void> {
  if (inFlight) return;
  if (!window.babyMenu) {
    setState({ status: "error", message: "baby menu bridge unavailable" });
    return;
  }
  inFlight = true;
  try {
    const result = await window.babyMenu.capabilities.invoke<SampleResult>(EXTENSION_ID, "getSample");
    if (result.ok) {
      setState({ status: "ready", sample: result.data, stale: false });
    } else if (state.status === "ready") {
      setState({ ...state, stale: true });
    } else {
      setState({ status: "error", message: result.error });
    }
  } catch (err) {
    if (state.status === "ready") {
      setState({ ...state, stale: true });
    } else {
      setState({ status: "error", message: err instanceof Error ? err.message : "failed to sample system usage" });
    }
  } finally {
    inFlight = false;
  }
}

let ramAppsState: RamAppsState = { status: "idle" };
let ramAppsListeners: Array<() => void> = [];
let ramAppsInFlight = false;

function setRamAppsState(next: RamAppsState) {
  ramAppsState = next;
  for (const listener of ramAppsListeners) listener();
}

function subscribeRamApps(listener: () => void): () => void {
  ramAppsListeners.push(listener);
  return () => {
    ramAppsListeners = ramAppsListeners.filter((l) => l !== listener);
  };
}

function getRamAppsSnapshot(): RamAppsState {
  return ramAppsState;
}

export function useRamAppsState(): RamAppsState {
  return useSyncExternalStore(subscribeRamApps, getRamAppsSnapshot);
}

export async function refreshRamApps(): Promise<void> {
  if (ramAppsInFlight) return;
  if (!window.babyMenu) {
    setRamAppsState({ status: "error", message: "baby menu bridge unavailable" });
    return;
  }
  ramAppsInFlight = true;
  if (ramAppsState.status !== "ready") setRamAppsState({ status: "loading" });
  try {
    const result = await window.babyMenu.capabilities.invoke<RamAppsResult>(EXTENSION_ID, "getTopRamApps");
    if (result.ok) setRamAppsState({ status: "ready", apps: result.data.apps });
    else if (ramAppsState.status !== "ready") setRamAppsState({ status: "error", message: result.error });
  } catch (err) {
    if (ramAppsState.status !== "ready") {
      setRamAppsState({
        status: "error",
        message: err instanceof Error ? err.message : "failed to list top ram apps",
      });
    }
  } finally {
    ramAppsInFlight = false;
  }
}

export function meterTone(percent: number): "live" | "warn" | "danger" {
  if (percent >= 90) return "danger";
  if (percent >= 70) return "warn";
  return "live";
}

export function formatGib(bytes: number): string {
  return `${(bytes / 1024 ** 3).toFixed(1)}`;
}
