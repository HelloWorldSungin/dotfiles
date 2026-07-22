import React, { useEffect } from "react";
import { StatusDot } from "@babymenu/ui";
import { refreshCodexQuota, useCodexQuotaState } from "./store";

function CircleProgress({ percentLeft, label }: { percentLeft: number; label: string }) {
  const size = 64;
  const strokeWidth = 3;
  const radius = size / 2;
  const normalizedRadius = radius - strokeWidth;
  const circumference = normalizedRadius * 2 * Math.PI;
  const strokeDashoffset = circumference - (percentLeft / 100) * circumference;

  return (
    <div className="flex flex-col items-center gap-1 shrink-0">
      <div className="relative flex items-center justify-center h-16 w-16 select-none">
        <svg viewBox="0 0 64 64" className="absolute top-0 left-0 h-full w-full transform -rotate-90">
          <circle
            className="stroke-current text-ink-soft opacity-10"
            fill="transparent"
            strokeWidth={strokeWidth}
            r={normalizedRadius}
            cx={radius}
            cy={radius}
          />
          <circle
            className="stroke-current text-signal-live transition-all duration-300"
            fill="transparent"
            strokeWidth={strokeWidth}
            strokeDasharray={`${circumference} ${circumference}`}
            style={{ strokeDashoffset }}
            strokeLinecap="round"
            r={normalizedRadius}
            cx={radius}
            cy={radius}
          />
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center leading-none">
          <div className="flex items-baseline justify-center">
            <span className="text-md font-mono font-light tracking-tight text-ink-strong">
              {Math.round(percentLeft)}
            </span>
            <span className="text-[10px] font-mono text-ink-soft ml-0.5">%</span>
          </div>
          <span className="text-[8px] uppercase tracking-caps font-mono text-ink-soft mt-0.5">left</span>
        </div>
      </div>
      <span className="text-[10px] uppercase tracking-caps text-ink-label font-mono text-center mt-1 truncate max-w-[72px]">{label}</span>
    </div>
  );
}

function formatRefreshedAt(isoString?: string) {
  if (!isoString) return "";
  const date = new Date(isoString);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" }).toLowerCase();
}

export function CodexQuotaView() {
  const state = useCodexQuotaState();

  useEffect(() => {
    void refreshCodexQuota();
  }, []);

  const weeklyWindow = state.status === "ready" ? state.snapshot.windows[0] : undefined;

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label border-b border-line-faint/10 pb-1">
        <span>codex · weekly</span>
        {state.status === "ready" ? (
          <span className="flex items-center gap-1.5">
            <StatusDot tone={state.snapshot.stale ? "warn" : "live"} />
            {state.snapshot.stale ? "stale" : state.snapshot.source}
          </span>
        ) : null}
      </div>

      {state.status === "loading" ? <span className="text-sm text-ink-muted">loading…</span> : null}
      {state.status === "error" ? <span className="text-sm text-signal-danger">{state.message}</span> : null}

      {state.status === "ready" ? (
        <div className="flex flex-col gap-3">
          <div className="flex items-center gap-5 py-1">
            {weeklyWindow ? (
              <CircleProgress
                percentLeft={100 - (weeklyWindow.percentUsed ?? 0)}
                label="week limit"
              />
            ) : null}
            <div className="flex-1 flex flex-col gap-1 justify-center">
              <div className="flex flex-col">
                <span className="text-xxs uppercase tracking-caps text-ink-label font-mono">credits</span>
                <span className="text-sm font-light tracking-value text-ink-strong">
                  {state.snapshot.plan || "PRO"}
                </span>
              </div>
              {state.snapshot.accountEmail ? (
                <div className="flex flex-col mt-1">
                  <span className="text-xxs uppercase tracking-caps text-ink-label font-mono">account</span>
                  <span className="text-xs text-ink-muted truncate">{state.snapshot.accountEmail}</span>
                </div>
              ) : null}
            </div>
          </div>

          <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label border-t border-line-faint/10 pt-2 mt-1">
            <span className="font-mono">
              {weeklyWindow?.resetText ? `resets ${weeklyWindow.resetText}` : "weekly reset"}
            </span>
            <div className="flex items-center gap-1.5 font-mono">
              <span>{formatRefreshedAt(state.snapshot.refreshedAt)}</span>
              <span>·</span>
              <button
                type="button"
                onClick={() => void refreshCodexQuota()}
                className="text-signal-live hover:underline cursor-pointer lowercase"
              >
                refresh
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}
