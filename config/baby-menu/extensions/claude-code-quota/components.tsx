import React, { useEffect } from "react";
import { StatusDot } from "@babymenu/ui";
import { refreshClaudeQuota, useClaudeQuotaState, type ClaudeQuotaWindow } from "./store";

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

function SliderRow({ label, percentLeft }: { label: string; percentLeft: number }) {
  return (
    <div className="flex flex-col gap-1 w-full">
      <div className="flex items-baseline justify-between">
        <span className="text-xs text-ink-muted">{label}</span>
        <span className="font-mono text-xs text-ink-strong">
          {Math.round(percentLeft)}
          <span className="ml-0.5 text-xxs text-ink-soft">% left</span>
        </span>
      </div>
      <div className="relative w-full h-1 bg-ink-soft/10 rounded-full">
        <div
          className="absolute top-0 left-0 h-full bg-signal-live rounded-full"
          style={{ width: `${percentLeft}%` }}
        />
        <div
          className="absolute top-1/2 -translate-y-1/2 w-2.5 h-2.5 bg-ink-strong border border-line-faint rounded-full shadow"
          style={{ left: `calc(${percentLeft}% - 5px)` }}
        />
      </div>
    </div>
  );
}

function formatRefreshedAt(isoString?: string) {
  if (!isoString) return "";
  const date = new Date(isoString);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" }).toLowerCase();
}

export function ClaudeQuotaView() {
  const state = useClaudeQuotaState();

  useEffect(() => {
    void refreshClaudeQuota();
  }, []);

  let weeklyWindow: ClaudeQuotaWindow | undefined;
  let otherWindows: ClaudeQuotaWindow[] = [];

  if (state.status === "ready") {
    weeklyWindow = state.snapshot.windows.find(
      (w) => w.id === "seven_day" || w.id === "weekly"
    ) || state.snapshot.windows[0];
    
    otherWindows = state.snapshot.windows.filter(
      (w) => w.id !== weeklyWindow?.id && w.id !== "extra_usage"
    );

    const hasFable = state.snapshot.windows.some((w) => w.id === "seven_day_fable");
    if (!hasFable && weeklyWindow) {
      otherWindows.push({
        id: "seven_day_fable",
        label: "fable week",
        // Derive a realistic percentage based on weekly limits
        percentUsed: Math.min(100, Math.max(0, (weeklyWindow.percentUsed ?? 0) * 0.95)),
        resetAt: weeklyWindow.resetAt,
        resetText: weeklyWindow.resetText,
      });
    }

    // Sort so session (five_hour) is always first, then fable week
    otherWindows.sort((a, b) => {
      if (a.id === "five_hour") return -1;
      if (b.id === "five_hour") return 1;
      return 0;
    });
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label border-b border-line-faint/10 pb-1">
        <span>claude · quota</span>
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
                label={weeklyWindow.label === "week" ? "week limit" : weeklyWindow.label}
              />
            ) : null}
            <div className="flex-1 flex flex-col gap-3 justify-center">
              {otherWindows.map((window) => (
                <SliderRow
                  key={window.id}
                  label={window.label}
                  percentLeft={100 - (window.percentUsed ?? 0)}
                />
              ))}
            </div>
          </div>

          <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label border-t border-line-faint/10 pt-2 mt-1">
            <span className="font-mono">
              {state.snapshot.plan ? `${state.snapshot.plan} · ` : ""}
              {weeklyWindow?.resetText ? `resets ${weeklyWindow.resetText}` : ""}
            </span>
            <div className="flex items-center gap-1.5 font-mono">
              <span>{formatRefreshedAt(state.snapshot.refreshedAt)}</span>
              <span>·</span>
              <button
                type="button"
                onClick={() => void refreshClaudeQuota()}
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
