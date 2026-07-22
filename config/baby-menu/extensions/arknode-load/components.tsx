import { useState } from "react";
import { Skeleton, StatusDot } from "@babymenu/ui";
import {
  formatGib,
  meterTone,
  useArknodeState,
  type ArknodeSample,
  type ContainerUsage,
  type GpuUsage,
} from "./store";

type Metric = "cpu" | "gpu" | "ram" | "disk";

function MeterRow({
  label,
  percent,
  detail,
  onClick,
  expanded,
  children,
}: {
  label: string;
  percent?: number;
  detail?: string;
  onClick: () => void;
  expanded: boolean;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-1 w-full">
      <button
        type="button"
        onClick={onClick}
        className="flex cursor-pointer flex-col gap-1 w-full rounded-xs text-left hover:bg-ink-soft/5 p-1 transition-colors group"
      >
        <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label font-mono w-full">
          <span className="flex items-center gap-1.5">
            {label}
            <span className="text-ink-soft normal-case font-mono">{expanded ? "−" : "+"}</span>
          </span>
          {detail ? <span className="lowercase text-ink-muted normal-case font-mono">{detail}</span> : null}
        </div>
        <div className="flex items-center gap-4 w-full">
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
          <div className="flex-1 relative h-1 bg-ink-soft/10 rounded-full overflow-hidden">
            <div
              className="absolute top-0 left-0 h-full bg-signal-live rounded-full transition-all duration-300"
              style={{ width: `${Math.min(100, Math.max(0, percent ?? 0))}%` }}
            />
          </div>
        </div>
      </button>
      {expanded ? children : null}
    </div>
  );
}

function ContainerRow({
  ct,
  percent,
  detail,
}: {
  ct: ContainerUsage;
  percent?: number;
  detail: string;
}) {
  return (
    <div className="flex items-center gap-2 py-0.5">
      <span className="w-14 shrink-0 text-xxs uppercase tracking-caps font-mono text-ink-label">ct{ct.vmid}</span>
      <span className="w-24 shrink-0 truncate text-sm text-ink">{ct.name}</span>
      <div className="min-w-0 flex-1 relative h-1 bg-ink-soft/10 rounded-full overflow-hidden">
        <div
          className="absolute top-0 left-0 h-full bg-signal-live rounded-full transition-all duration-300"
          style={{ width: `${Math.min(100, Math.max(0, percent ?? 0))}%` }}
        />
      </div>
      <span className="w-9 shrink-0 text-right text-sm tracking-value font-mono text-ink-strong">
        {percent === undefined ? <span className="text-ink-soft">--</span> : `${Math.round(percent)}%`}
      </span>
      <span className="w-24 shrink-0 text-right text-xxs font-mono text-ink-muted">{detail}</span>
    </div>
  );
}

function ContainerPanel({
  containers,
  metric,
}: {
  containers: ContainerUsage[];
  metric: "cpu" | "ram" | "disk";
}) {
  return (
    <div className="flex flex-col gap-1.5 pt-1 pl-2 border-l border-line-faint/20 my-1">
      <span className="text-xxs uppercase tracking-caps font-mono text-ink-label">per container</span>
      {containers.map((ct) => {
        if (metric === "cpu") {
          return (
            <ContainerRow
              key={ct.vmid}
              ct={ct}
              percent={ct.cpuPercent}
              detail={ct.cpuPercent === undefined ? "warming up" : `${ct.cpus} cores`}
            />
          );
        }
        if (metric === "ram") {
          return (
            <ContainerRow
              key={ct.vmid}
              ct={ct}
              percent={ct.memPercent}
              detail={`${formatGib(ct.memUsedBytes)}/${formatGib(ct.memTotalBytes)} GiB`}
            />
          );
        }
        return (
          <ContainerRow
            key={ct.vmid}
            ct={ct}
            percent={ct.diskPercent}
            detail={`${formatGib(ct.diskUsedBytes)}/${formatGib(ct.diskTotalBytes)} GiB`}
          />
        );
      })}
    </div>
  );
}

function GpuRow({ gpu }: { gpu: GpuUsage }) {
  return (
    <div className="flex flex-col gap-1 py-0.5">
      <div className="flex items-center gap-2">
        <span className="w-14 shrink-0 text-xxs uppercase tracking-caps font-mono text-ink-label">gpu {gpu.index}</span>
        <div className="min-w-0 flex-1 relative h-1 bg-ink-soft/10 rounded-full overflow-hidden">
          <div
            className="absolute top-0 left-0 h-full bg-signal-live rounded-full transition-all duration-300"
            style={{ width: `${Math.min(100, Math.max(0, gpu.utilPercent))}%` }}
          />
        </div>
        <span className="w-9 shrink-0 text-right text-sm tracking-value font-mono text-ink-strong">
          {Math.round(gpu.utilPercent)}%
        </span>
      </div>
      <div className="flex justify-between pl-16 text-xxs font-mono text-ink-muted">
        <span>fan {gpu.fanPercent === undefined ? "--" : `${Math.round(gpu.fanPercent)}%`}</span>
        <span>{gpu.tempC === undefined ? "" : `${gpu.tempC}°C`}</span>
        <span>
          vram {formatGib(gpu.vramUsedBytes)}/{formatGib(gpu.vramTotalBytes)} GiB
        </span>
      </div>
    </div>
  );
}

function GpuPanel({ sample }: { sample: ArknodeSample }) {
  const gpuCts = sample.containers.filter((ct) => ct.hasGpu);
  return (
    <div className="flex flex-col gap-2 pt-1 pl-2 border-l border-line-faint/20 my-1">
      <div className="flex items-baseline justify-between">
        <span className="text-xxs uppercase tracking-caps font-mono text-ink-label">per gpu</span>
        {gpuCts.length > 0 ? (
          <span className="text-xxs font-mono text-ink-muted">
            passed to {gpuCts.map((ct) => `ct${ct.vmid} ${ct.name}`).join(", ")}
          </span>
        ) : null}
      </div>
      {sample.gpus.length === 0 ? (
        <span className="text-sm text-ink-muted">no gpu telemetry available</span>
      ) : (
        sample.gpus.map((gpu) => <GpuRow key={gpu.index} gpu={gpu} />)
      )}
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

export function ArknodeLoadView() {
  const state = useArknodeState();
  const [expanded, setExpanded] = useState<Metric | null>(null);

  const toggle = (metric: Metric) => setExpanded((current) => (current === metric ? null : metric));

  const gpuAverage =
    state.status === "ready" && state.sample.gpus.length > 0
      ? state.sample.gpus.reduce((sum, gpu) => sum + gpu.utilPercent, 0) / state.sample.gpus.length
      : undefined;

  const online = state.status === "ready" && !state.stale;

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label border-b border-line-faint/10 pb-1 font-mono">
        <span>arknode-ai load</span>
        {online ? (
          <span className="flex items-center gap-1.5 text-signal-live">
            <StatusDot tone="live" /> live
          </span>
        ) : (
          <span className="flex items-center gap-1.5 text-ink-soft">
            <StatusDot tone="muted" /> live
          </span>
        )}
      </div>

      {state.status === "loading" ? <LoadingBody /> : null}

      {online ? (
        <div className="flex flex-col gap-3">
          <MeterRow
            label="cpu"
            percent={state.sample.host.cpuPercent}
            detail={
              state.sample.host.cpuPercent === undefined
                ? "warming up"
                : `${state.sample.host.cpuCount} threads`
            }
            onClick={() => toggle("cpu")}
            expanded={expanded === "cpu"}
          >
            <ContainerPanel containers={state.sample.containers} metric="cpu" />
          </MeterRow>
          <MeterRow
            label="gpu"
            percent={gpuAverage}
            detail={
              state.sample.gpus.length > 0
                ? `${state.sample.gpus.length}x ${state.sample.gpus[0].name.replace(/^NVIDIA\s+/, "")}`
                : "unavailable"
            }
            onClick={() => toggle("gpu")}
            expanded={expanded === "gpu"}
          >
            <GpuPanel sample={state.sample} />
          </MeterRow>
          <MeterRow
            label="ram"
            percent={state.sample.host.ramPercent}
            detail={`${formatGib(state.sample.host.ramUsedBytes)} / ${formatGib(state.sample.host.ramTotalBytes)} GB mem`}
            onClick={() => toggle("ram")}
            expanded={expanded === "ram"}
          >
            <ContainerPanel containers={state.sample.containers} metric="ram" />
          </MeterRow>
          <MeterRow
            label="disk"
            percent={state.sample.host.diskPercent}
            detail={`${formatGib(state.sample.host.diskUsedBytes)} / ${formatGib(state.sample.host.diskTotalBytes)} GB disk`}
            onClick={() => toggle("disk")}
            expanded={expanded === "disk"}
          >
            <ContainerPanel containers={state.sample.containers} metric="disk" />
          </MeterRow>
        </div>
      ) : null}
    </div>
  );
}
