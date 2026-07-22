import { useSyncExternalStore } from "react";

export type GithubDay = {
  date: string;
  level: number;
};

export type GithubStatusSnapshot = {
  username: string;
  name?: string;
  totalContributions: number;
  currentStreak: number;
  stars: number;
  publicRepos: number;
  days: GithubDay[];
  refreshedAt: string;
  stale: boolean;
};

export type GithubState =
  | { status: "loading" }
  | { status: "ready"; snapshot: GithubStatusSnapshot }
  | { status: "error"; message: string };

const EXTENSION_ID = "github-status";

let state: GithubState = { status: "loading" };
let listeners: Array<() => void> = [];
let inFlight = false;

function setState(next: GithubState) {
  state = next;
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void): () => void {
  listeners.push(listener);
  return () => {
    listeners = listeners.filter((l) => l !== listener);
  };
}

function getSnapshot(): GithubState {
  return state;
}

export function useGithubState(): GithubState {
  return useSyncExternalStore(subscribe, getSnapshot);
}

export async function refreshGithubStatus(): Promise<void> {
  if (inFlight) return;
  if (!window.babyMenu) {
    setState({ status: "error", message: "Baby Menu bridge unavailable" });
    return;
  }
  inFlight = true;
  try {
    const result = await window.babyMenu.capabilities.invoke<{ ok: boolean; data?: GithubStatusSnapshot; error?: string }>(
      EXTENSION_ID,
      "getContributions"
    );
    if (result.ok && result.data) {
      setState({ status: "ready", snapshot: result.data });
    } else {
      setState({ status: "error", message: result.error || "Failed to load GitHub activity" });
    }
  } catch (err) {
    setState({ status: "error", message: err instanceof Error ? err.message : "Failed to load GitHub" });
  } finally {
    inFlight = false;
  }
}

export async function saveGithubUsername(username: string): Promise<boolean> {
  if (!window.babyMenu) return false;
  try {
    const result = await window.babyMenu.capabilities.invoke<{ ok: boolean; error?: string }>(
      EXTENSION_ID,
      "saveUsername",
      { username }
    );
    if (result.ok) {
      void refreshGithubStatus();
      return true;
    }
    return false;
  } catch (err) {
    console.error(err);
    return false;
  }
}

export async function fetchGithubUsername(): Promise<string> {
  if (!window.babyMenu) return "";
  try {
    const result = await window.babyMenu.capabilities.invoke<{ ok: boolean; username: string }>(
      EXTENSION_ID,
      "getUsername"
    );
    return result.username;
  } catch {
    return "";
  }
}
