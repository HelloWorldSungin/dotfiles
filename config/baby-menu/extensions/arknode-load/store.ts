import { useSyncExternalStore } from "react";

export type ContainerUsage = {
  vmid: number;
  name: string;
  status: string;
  cpus: number;
  cpuPercent?: number;
  memPercent: number;
  memUsedBytes: number;
  memTotalBytes: number;
  diskPercent: number;
  diskUsedBytes: number;
  diskTotalBytes: number;
  hasGpu: boolean;
};

export type GpuUsage = {
  index: number;
  name: string;
  utilPercent: number;
  fanPercent?: number;
  tempC?: number;
  vramUsedBytes: number;
  vramTotalBytes: number;
};

export type ArknodeSample = {
  host: {
    cpuPercent?: number;
    cpuCount: number;
    cpuModel?: string;
    ramPercent: number;
    ramUsedBytes: number;
    ramTotalBytes: number;
    diskPercent: number;
    diskUsedBytes: number;
    diskTotalBytes: number;
  };
  containers: ContainerUsage[];
  gpus: GpuUsage[];
  sampledAt: string;
};

type SampleResult = { ok: true; data: ArknodeSample } | { ok: false; error: string };

export type ArknodeState =
  | { status: "loading" }
  | { status: "ready"; sample: ArknodeSample; stale: boolean }
  | { status: "error"; message: string };

const EXTENSION_ID = "arknode-load";

let state: ArknodeState = { status: "loading" };
let listeners: Array<() => void> = [];
let inFlight = false;

function setState(next: ArknodeState) {
  state = next;
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void): () => void {
  listeners.push(listener);
  return () => {
    listeners = listeners.filter((l) => l !== listener);
  };
}

function getSnapshot(): ArknodeState {
  return state;
}

export function useArknodeState(): ArknodeState {
  return useSyncExternalStore(subscribe, getSnapshot);
}

export async function refreshArknodeLoad(): Promise<void> {
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
      setState({ status: "error", message: err instanceof Error ? err.message : "failed to reach arknode-ai" });
    }
  } finally {
    inFlight = false;
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
