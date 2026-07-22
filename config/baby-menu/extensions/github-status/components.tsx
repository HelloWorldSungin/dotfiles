import React, { useEffect } from "react";
import { cn, StatusDot } from "@babymenu/ui";
import { refreshGithubStatus, useGithubState, type GithubDay } from "./store";

function getLevelColorClass(level: number): string {
  switch (level) {
    case 1:
      return "bg-signal-live opacity-30";
    case 2:
      return "bg-signal-live opacity-55";
    case 3:
      return "bg-signal-live opacity-80";
    case 4:
      return "bg-signal-live"; // full bright mint
    default:
      return "bg-ink-soft/15"; // very dark gray/black
  }
}

function formatRefreshedAt(isoString?: string) {
  if (!isoString) return "";
  const date = new Date(isoString);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" }).toLowerCase();
}

export function GithubStatusView() {
  const state = useGithubState();

  useEffect(() => {
    void refreshGithubStatus();
  }, []);

  if (state.status === "loading") {
    return (
      <div className="flex flex-col gap-2 py-2">
        <span className="text-sm text-ink-muted">loading github status…</span>
      </div>
    );
  }

  if (state.status === "error") {
    return (
      <div className="flex flex-col gap-2 py-2 text-signal-danger">
        <span className="text-xs uppercase tracking-caps text-ink-label border-b border-line-faint/10 pb-1">github status</span>
        <span className="text-sm">{state.message}</span>
      </div>
    );
  }

  const { snapshot } = state;
  const days = snapshot.days || [];

  // Group days into weeks starting Sunday (day 0)
  const weeks: GithubDay[][] = [];
  let currentWeek: GithubDay[] = [];

  if (days.length > 0) {
    // Fill empty slots at start of first week if not Sunday
    const firstDay = new Date(days[0].date + "T00:00:00");
    const firstDayOfWeek = firstDay.getDay(); // 0 = Sunday
    for (let i = 0; i < firstDayOfWeek; i++) {
      currentWeek.push({ date: "", level: 0 });
    }

    for (const day of days) {
      const dateObj = new Date(day.date + "T00:00:00");
      if (dateObj.getDay() === 0 && currentWeek.length > 0) {
        weeks.push(currentWeek);
        currentWeek = [];
      }
      currentWeek.push(day);
    }

    if (currentWeek.length > 0) {
      while (currentWeek.length < 7) {
        currentWeek.push({ date: "", level: 0 });
      }
      weeks.push(currentWeek);
    }
  }

  return (
    <div className="flex flex-col gap-3">
      {/* Title Header */}
      <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label border-b border-line-faint/10 pb-1">
        <span>github · {snapshot.username}</span>
        <span className="flex items-center gap-1.5 text-signal-live">
          <StatusDot tone={snapshot.stale ? "warn" : "live"} />
          {snapshot.stale ? "stale" : "live"}
        </span>
      </div>

      {/* User Header Info */}
      <div className="flex items-baseline justify-between py-1">
        <div className="flex flex-col">
          <span className="text-lg font-light tracking-value text-ink-strong truncate max-w-[200px]">
            {snapshot.name || snapshot.username}
          </span>
          <span className="text-xxs uppercase tracking-caps text-ink-label font-mono">
            {snapshot.totalContributions.toLocaleString()} activity
          </span>
        </div>
        {snapshot.currentStreak > 0 ? (
          <span className="text-xxs uppercase tracking-caps font-mono bg-signal-live/10 text-signal-live px-2 py-0.5 rounded-sm">
            {snapshot.currentStreak} day streak
          </span>
        ) : null}
      </div>

      {/* Contribution Grid */}
      {weeks.length > 0 ? (
        <div className="flex gap-[3px] overflow-x-auto pb-1 select-none max-w-full justify-between">
          {weeks.map((week, wIndex) => (
            <div key={wIndex} className="flex flex-col gap-[3px] shrink-0">
              {week.map((day, dIndex) => (
                <div
                  key={dIndex}
                  className={cn(
                    "h-2 w-2 rounded-[1px] transition-colors duration-200",
                    day.date === "" ? "opacity-0" : getLevelColorClass(day.level)
                  )}
                  title={day.date ? `${day.date}: level ${day.level}` : undefined}
                />
              ))}
            </div>
          ))}
        </div>
      ) : (
        <span className="text-xs text-ink-muted text-center py-2">no contribution data available</span>
      )}

      {/* Repository & Stars Metadata */}
      <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label font-mono border-t border-line-faint/10 pt-2 mt-1">
        <span>
          {snapshot.publicRepos} owned repos · {snapshot.stars} stars
        </span>
        <div className="flex items-center gap-1.5 font-mono">
          <span>{formatRefreshedAt(snapshot.refreshedAt)}</span>
          <span>·</span>
          <button
            type="button"
            onClick={() => void refreshGithubStatus()}
            className="text-signal-live hover:underline cursor-pointer lowercase"
          >
            refresh
          </button>
        </div>
      </div>
    </div>
  );
}
