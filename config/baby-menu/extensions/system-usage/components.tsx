import React, { useState, useEffect } from "react";
import { Skeleton, StatusDot } from "@babymenu/ui";
import { formatGib, refreshRamApps, refreshSystemUsage, useRamAppsState, useSystemUsageState, type RamApp } from "./store";

function MeterRow({
  label,
  percent,
  detail,
  onClick,
  children,
}: {
  label: string;
  percent?: number;
  detail?: string;
  onClick?: () => void;
  children?: React.ReactNode;
}) {
  const body = (
    <div className="flex flex-col gap-1 w-full py-1">
      <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label font-mono">
        <span>{label}</span>
        {detail ? <span className="lowercase text-ink-muted normal-case font-mono">{detail}</span> : null}
      </div>
      <div className="flex items-center gap-4">
        <span className="text-2xl font-light tracking-value text-ink-strong w-[68px] shrink-0">
          {percent === undefined ? (
            <span className="text-sm text-ink-soft">--</span>
          ) : (
            <>
              {Math.round(percent)}
              <span className="ml-0.5 text-xs text-ink-soft">%</span>
            </>
          )}
        </span>
        <div className="flex-1 relative h-1 bg-ink-soft/10 rounded-full">
          <div
            className="absolute top-0 left-0 h-full bg-signal-live rounded-full transition-all duration-300"
            style={{ width: `${percent ?? 0}%` }}
          />
        </div>
      </div>
    </div>
  );

  if (!onClick) {
    return <div className="flex flex-col gap-1">{body}</div>;
  }
  return (
    <div className="flex flex-col gap-1 w-full">
      <button
        type="button"
        onClick={onClick}
        className="flex cursor-pointer flex-col gap-1 rounded-xs text-left hover:bg-elevated w-full"
      >
        {body}
      </button>
      {children}
    </div>
  );
}

function RamAppRow({ app }: { app: RamApp }) {
  return (
    <div className="flex items-center gap-2">
      {app.iconDataUrl ? (
        <img src={app.iconDataUrl} alt="" className="h-5 w-5 rounded-xs" />
      ) : (
        <span className="flex h-5 w-5 items-center justify-center rounded-xs bg-elevated text-xxs text-ink-soft">
          {app.name.slice(0, 1).toUpperCase()}
        </span>
      )}
      <span className="min-w-0 flex-1 truncate text-sm text-ink">{app.name}</span>
      <span className="text-sm tracking-value text-ink-strong">
        {formatGib(app.memoryBytes)}
        <span className="ml-0.5 text-xxs text-ink-soft">GiB</span>
      </span>
    </div>
  );
}

function RamAppsPanel() {
  const state = useRamAppsState();

  return (
    <div className="flex flex-col gap-2 pt-1">
      <span className="text-xxs uppercase tracking-caps text-ink-label">top apps</span>
      {state.status === "loading" || state.status === "idle" ? (
        <div className="flex flex-col gap-2">
          <Skeleton className="h-5 w-full" />
          <Skeleton className="h-5 w-full" />
          <Skeleton className="h-5 w-full" />
        </div>
      ) : null}
      {state.status === "error" ? <span className="text-sm text-ink-muted">{state.message}</span> : null}
      {state.status === "ready"
        ? state.apps.map((app) => <RamAppRow key={app.name} app={app} />)
        : null}
    </div>
  );
}

function LoadingBody() {
  return (
    <div className="flex flex-col gap-3">
      <Skeleton className="h-10 w-full" />
      <Skeleton className="h-10 w-full" />
      <Skeleton className="h-10 w-full" />
      <Skeleton className="h-10 w-full" />
    </div>
  );
}

function formatRefreshedAt(isoString?: string) {
  if (!isoString) return "";
  const date = new Date(isoString);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit", second: "2-digit" }).toLowerCase();
}

export function SystemUsageView() {
  const state = useSystemUsageState();
  const [ramExpanded, setRamExpanded] = useState(false);

  useEffect(() => {
    void refreshSystemUsage();
  }, []);

  const toggleRamApps = () => {
    setRamExpanded((expanded) => {
      if (!expanded) void refreshRamApps();
      return !expanded;
    });
  };

  const hasGpu = state.status === "ready" && state.sample.gpuPercent !== undefined && state.sample.gpuPercent > 0;

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label border-b border-line-faint/10 pb-1">
        <span>system usage</span>
        {state.status === "ready" ? (
          state.stale ? (
            <span className="flex items-center gap-1.5 text-signal-warn">
              <StatusDot tone="warn" /> stale
            </span>
          ) : (
            <span className="flex items-center gap-1.5 text-signal-live">
              <StatusDot tone="live" /> live
            </span>
          )
        ) : null}
      </div>

      {state.status === "loading" ? <LoadingBody /> : null}

      {state.status === "error" ? (
        <div className="flex items-center gap-1.5 text-sm text-ink-muted">
          <StatusDot tone="danger" /> {state.message}
        </div>
      ) : null}

      {state.status === "ready" ? (
        <div className="flex flex-col gap-3">
          <MeterRow
            label="disk"
            percent={state.sample.diskPercent}
            detail={`${formatGib(state.sample.diskUsedBytes)} / ${formatGib(state.sample.diskTotalBytes)} GB`}
          />
          <MeterRow
            label="cpu"
            percent={state.sample.cpuPercent}
            detail={state.sample.cpuPercent === undefined ? "warming up" : undefined}
          />
          {hasGpu ? (
            <MeterRow
              label="gpu"
              percent={state.sample.gpuPercent}
            />
          ) : null}
          <MeterRow
            label="ram"
            percent={state.sample.ramPercent}
            detail={`${formatGib(state.sample.ramUsedBytes)} / ${formatGib(state.sample.ramTotalBytes)} GB mem`}
            onClick={toggleRamApps}
          >
            {ramExpanded ? <RamAppsPanel /> : null}
          </MeterRow>

          <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label border-t border-line-faint/10 pt-2 mt-1">
            <span className="font-mono">hardware</span>
            <div className="flex items-center gap-1.5 font-mono">
              <span>{formatRefreshedAt(state.sample.sampledAt)}</span>
              <span>·</span>
              <button
                type="button"
                onClick={() => void refreshSystemUsage()}
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
