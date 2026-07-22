import { execFile } from "node:child_process";
import type { BabyMenuDatabase, BabyMenuServerContext } from "@babymenu/contracts";

const SSH_TARGET = "root@192.168.68.10";
const SSH_TIMEOUT_MS = 12_000;
const BASELINE_TABLE = "arknode_load_cpu_baseline";

// One SSH round trip gathers everything: node status, per-container stats,
// storage, GPU telemetry, and raw CPU counters for rate math on our side.
const REMOTE_SCRIPT = [
  "node=$(hostname)",
  "echo ===NODE===",
  "pvesh get /nodes/$node/status --output-format json",
  "echo ===LXC===",
  "pvesh get /nodes/$node/lxc --output-format json",
  "echo ===STORAGE===",
  "pvesh get /nodes/$node/storage --output-format json",
  "echo ===GPU===",
  "nvidia-smi --query-gpu=index,name,utilization.gpu,fan.speed,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null",
  "echo ===STAT===",
  "head -1 /proc/stat",
  "echo ===TIME===",
  "date +%s%3N",
  "echo ===CG===",
  "for d in /sys/fs/cgroup/lxc/*/cpu.stat; do echo $(basename $(dirname $d)) $(awk '/^usage_usec/{print $2}' $d); done",
  "echo ===GPUCT===",
  "grep -l nvidia /etc/pve/lxc/*.conf 2>/dev/null",
  "true",
].join("; ");

export type ContainerUsage = {
  vmid: number;
  name: string;
  status: string;
  cpus: number;
  // percent of this container's own cpu allocation; undefined while warming up
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

export type SampleResult = { ok: true; data: ArknodeSample } | { ok: false; error: string };

function runSsh(): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(
      "ssh",
      ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5", SSH_TARGET, REMOTE_SCRIPT],
      { timeout: SSH_TIMEOUT_MS, maxBuffer: 4 * 1024 * 1024 },
      (err, stdout, stderr) => {
        if (err) {
          const detail = stderr.toString().trim().split("\n")[0];
          reject(new Error(detail || err.message));
        } else {
          resolve(stdout.toString());
        }
      },
    );
  });
}

function splitSections(output: string): Map<string, string> {
  const sections = new Map<string, string>();
  let current: string | undefined;
  let buffer: string[] = [];
  for (const line of output.split("\n")) {
    const match = line.match(/^===([A-Z]+)===\s*$/);
    if (match) {
      if (current) sections.set(current, buffer.join("\n").trim());
      current = match[1];
      buffer = [];
    } else if (current) {
      buffer.push(line);
    }
  }
  if (current) sections.set(current, buffer.join("\n").trim());
  return sections;
}

function clampPercent(value: number): number {
  return Math.min(100, Math.max(0, value));
}

// --- CPU baselines (host ticks + per-container cgroup usage) ---------------------

function ensureBaselineTable(db: BabyMenuDatabase) {
  db.exec(
    `CREATE TABLE IF NOT EXISTS ${BASELINE_TABLE} (scope TEXT PRIMARY KEY, active INTEGER NOT NULL, total INTEGER NOT NULL, at INTEGER NOT NULL)`,
  );
}

function diffBaseline(
  db: BabyMenuDatabase,
  scope: string,
  active: number,
  total: number,
  at: number,
): { active: number; total: number; at: number } | undefined {
  const previous = db.get<{ active: number; total: number; at: number }>(
    `SELECT active, total, at FROM ${BASELINE_TABLE} WHERE scope = ?`,
    [scope],
  );
  db.run(
    `INSERT INTO ${BASELINE_TABLE} (scope, active, total, at) VALUES (?, ?, ?, ?)
     ON CONFLICT(scope) DO UPDATE SET active = excluded.active, total = excluded.total, at = excluded.at`,
    [scope, active, total, at],
  );
  return previous;
}

// /proc/stat first line: cpu user nice system idle iowait irq softirq steal ...
function hostCpuPercent(db: BabyMenuDatabase, statLine: string): number | undefined {
  const fields = statLine.trim().split(/\s+/).slice(1).map(Number);
  if (fields.length < 5 || fields.some((n) => !Number.isFinite(n))) return undefined;
  const idle = fields[3] + fields[4]; // idle + iowait
  const total = fields.reduce((sum, n) => sum + n, 0);
  const active = total - idle;
  const previous = diffBaseline(db, "host", active, total, Date.now());
  if (!previous) return undefined;
  const totalDelta = total - previous.total;
  if (totalDelta <= 0) return undefined;
  return clampPercent(((active - previous.active) / totalDelta) * 100);
}

function containerCpuPercents(
  db: BabyMenuDatabase,
  cgSection: string,
  remoteMs: number,
  cpusByVmid: Map<number, number>,
): Map<number, number> {
  const percents = new Map<number, number>();
  for (const line of cgSection.split("\n")) {
    const match = line.trim().match(/^(\d+)\s+(\d+)$/);
    if (!match) continue;
    const vmid = Number(match[1]);
    const usageUsec = Number(match[2]);
    const previous = diffBaseline(db, `ct${vmid}`, usageUsec, 0, remoteMs);
    if (!previous) continue;
    const usageDelta = usageUsec - previous.active;
    const windowUsec = (remoteMs - previous.at) * 1000;
    const cpus = cpusByVmid.get(vmid) ?? 1;
    // negative delta means the container restarted; skip this window
    if (usageDelta < 0 || windowUsec <= 0) continue;
    percents.set(vmid, clampPercent((usageDelta / windowUsec / cpus) * 100));
  }
  return percents;
}

// --- section parsers --------------------------------------------------------------

type PveNodeStatus = {
  cpuinfo?: { cpus?: number; model?: string };
  memory?: { used?: number; total?: number };
};

type PveLxc = {
  vmid: number;
  name: string;
  status: string;
  cpus: number;
  mem: number;
  maxmem: number;
  disk: number;
  maxdisk: number;
};

type PveStorage = {
  storage: string;
  shared?: number;
  used?: number;
  total?: number;
  active?: number;
};

function parseGpus(section: string): GpuUsage[] {
  const gpus: GpuUsage[] = [];
  for (const line of section.split("\n")) {
    if (!line.trim()) continue;
    const parts = line.split(",").map((part) => part.trim());
    if (parts.length < 7) continue;
    const [index, name, util, fan, temp, vramUsed, vramTotal] = parts;
    const fanNum = Number(fan);
    const tempNum = Number(temp);
    gpus.push({
      index: Number(index),
      name,
      utilPercent: clampPercent(Number(util) || 0),
      fanPercent: Number.isFinite(fanNum) ? clampPercent(fanNum) : undefined,
      tempC: Number.isFinite(tempNum) ? tempNum : undefined,
      vramUsedBytes: (Number(vramUsed) || 0) * 1024 ** 2,
      vramTotalBytes: (Number(vramTotal) || 0) * 1024 ** 2,
    });
  }
  return gpus.sort((a, b) => a.index - b.index);
}

function parseGpuVmids(section: string): Set<number> {
  const vmids = new Set<number>();
  for (const line of section.split("\n")) {
    const match = line.match(/\/(\d+)\.conf\s*$/);
    if (match) vmids.add(Number(match[1]));
  }
  return vmids;
}

// --- action -----------------------------------------------------------------------

async function getSample(_input: unknown, context: BabyMenuServerContext): Promise<SampleResult> {
  try {
    const output = await runSsh();
    const sections = splitSections(output);

    const nodeJson = sections.get("NODE");
    const lxcJson = sections.get("LXC");
    if (!nodeJson || !lxcJson) throw new Error("unexpected output from arknode-ai");

    const node = JSON.parse(nodeJson) as PveNodeStatus;
    const lxcs = JSON.parse(lxcJson) as PveLxc[];
    const storages = JSON.parse(sections.get("STORAGE") ?? "[]") as PveStorage[];
    const gpus = parseGpus(sections.get("GPU") ?? "");
    const gpuVmids = parseGpuVmids(sections.get("GPUCT") ?? "");
    const remoteMs = Number(sections.get("TIME") ?? NaN);

    ensureBaselineTable(context.db);
    const cpuPercent = hostCpuPercent(context.db, sections.get("STAT") ?? "");
    const cpusByVmid = new Map(lxcs.map((ct) => [ct.vmid, ct.cpus]));
    const ctCpu = Number.isFinite(remoteMs)
      ? containerCpuPercents(context.db, sections.get("CG") ?? "", remoteMs, cpusByVmid)
      : new Map<number, number>();

    const ramTotal = node.memory?.total ?? 0;
    const ramUsed = node.memory?.used ?? 0;

    // Local storages only (rootfs + LVM-thin pool holding container disks);
    // the shared NFS backup target is not this box's disk.
    let diskUsed = 0;
    let diskTotal = 0;
    for (const storage of storages) {
      if (storage.shared === 1 || storage.active !== 1) continue;
      diskUsed += storage.used ?? 0;
      diskTotal += storage.total ?? 0;
    }

    const containers: ContainerUsage[] = lxcs
      .map((ct) => ({
        vmid: ct.vmid,
        name: ct.name,
        status: ct.status,
        cpus: ct.cpus,
        cpuPercent: ctCpu.get(ct.vmid),
        memPercent: ct.maxmem > 0 ? clampPercent((ct.mem / ct.maxmem) * 100) : 0,
        memUsedBytes: ct.mem,
        memTotalBytes: ct.maxmem,
        diskPercent: ct.maxdisk > 0 ? clampPercent((ct.disk / ct.maxdisk) * 100) : 0,
        diskUsedBytes: ct.disk,
        diskTotalBytes: ct.maxdisk,
        hasGpu: gpuVmids.has(ct.vmid),
      }))
      .sort((a, b) => a.vmid - b.vmid);

    return {
      ok: true,
      data: {
        host: {
          cpuPercent,
          cpuCount: node.cpuinfo?.cpus ?? 0,
          cpuModel: node.cpuinfo?.model,
          ramPercent: ramTotal > 0 ? clampPercent((ramUsed / ramTotal) * 100) : 0,
          ramUsedBytes: ramUsed,
          ramTotalBytes: ramTotal,
          diskPercent: diskTotal > 0 ? clampPercent((diskUsed / diskTotal) * 100) : 0,
          diskUsedBytes: diskUsed,
          diskTotalBytes: diskTotal,
        },
        containers,
        gpus,
        sampledAt: new Date().toISOString(),
      },
    };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : "failed to sample arknode-ai" };
  }
}

export const actions = {
  getSample,
};
