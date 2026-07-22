import { execFile } from "node:child_process";
import { readFile, readdir, unlink } from "node:fs/promises";
import { cpus, tmpdir, totalmem } from "node:os";
import { join } from "node:path";
import type { BabyMenuDatabase, BabyMenuServerContext } from "@babymenu/contracts";

type SystemUsageSample = {
  // undefined until a second reading exists to diff against (warming up)
  cpuPercent?: number;
  // undefined when no IOAccelerator utilization is exposed
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

type RamApp = {
  name: string;
  memoryBytes: number;
  // 64px PNG data URI extracted from the app bundle icon, when one exists
  iconDataUrl?: string;
};

type RamAppsResult = { ok: true; data: { apps: RamApp[]; sampledAt: string } } | { ok: false; error: string };

const BASELINE_TABLE = "system_usage_cpu_baseline";
const COMMAND_TIMEOUT_MS = 4000;

function run(command: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(command, args, { timeout: COMMAND_TIMEOUT_MS, maxBuffer: 4 * 1024 * 1024 }, (err, stdout) => {
      if (err) reject(err);
      else resolve(stdout.toString());
    });
  });
}

function clampPercent(value: number): number {
  return Math.min(100, Math.max(0, value));
}

// --- CPU: diff cumulative os.cpus() ticks against the persisted baseline ------

function readCpuTicks(): { active: number; total: number } {
  let active = 0;
  let total = 0;
  for (const cpu of cpus()) {
    const { user, nice, sys, idle, irq } = cpu.times;
    active += user + nice + sys + irq;
    total += user + nice + sys + irq + idle;
  }
  return { active, total };
}

function ensureBaselineTable(db: BabyMenuDatabase) {
  db.exec(
    `CREATE TABLE IF NOT EXISTS ${BASELINE_TABLE} (id INTEGER PRIMARY KEY CHECK (id = 1), active INTEGER NOT NULL, total INTEGER NOT NULL, at INTEGER NOT NULL)`,
  );
}

function sampleCpuPercent(db: BabyMenuDatabase): number | undefined {
  ensureBaselineTable(db);
  const now = readCpuTicks();
  const previous = db.get<{ active: number; total: number }>(
    `SELECT active, total FROM ${BASELINE_TABLE} WHERE id = 1`,
  );
  db.run(
    `INSERT INTO ${BASELINE_TABLE} (id, active, total, at) VALUES (1, ?, ?, ?)
     ON CONFLICT(id) DO UPDATE SET active = excluded.active, total = excluded.total, at = excluded.at`,
    [now.active, now.total, Date.now()],
  );
  if (!previous) return undefined;
  const totalDelta = now.total - previous.total;
  // No meaningful window yet (same tick, or ticks reset after reboot).
  if (totalDelta <= 0) return undefined;
  return clampPercent(((now.active - previous.active) / totalDelta) * 100);
}

// --- RAM: vm_stat page counts, Activity Monitor style used-memory formula -----

function vmStatPages(output: string, label: string): number | undefined {
  const match = output.match(new RegExp(`^${label}:\\s+(\\d+)\\.`, "m"));
  return match ? Number(match[1]) : undefined;
}

async function sampleRam(): Promise<{ percent: number; usedBytes: number; totalBytes: number }> {
  const output = await run("vm_stat", []);
  const pageSizeMatch = output.match(/page size of (\d+) bytes/);
  const pageSize = pageSizeMatch ? Number(pageSizeMatch[1]) : 16384;

  const anonymous = vmStatPages(output, "Anonymous pages");
  const purgeable = vmStatPages(output, "Pages purgeable");
  const wired = vmStatPages(output, "Pages wired down");
  const compressor = vmStatPages(output, "Pages occupied by compressor");
  if (anonymous === undefined || purgeable === undefined || wired === undefined || compressor === undefined) {
    throw new Error("unexpected vm_stat output");
  }

  const totalBytes = totalmem();
  // "memory used" as Activity Monitor reports it: app memory + wired + compressed
  const usedBytes = (anonymous - purgeable + wired + compressor) * pageSize;
  return {
    percent: clampPercent((usedBytes / totalBytes) * 100),
    usedBytes,
    totalBytes,
  };
}

// --- Disk: data-volume fullness via df ------------------------------------------

// The APFS data volume is what the user perceives as "my disk"; `df /` only
// covers the sealed system snapshot and reads misleadingly low.
const DATA_VOLUME = "/System/Volumes/Data";

async function sampleDisk(): Promise<{ percent: number; usedBytes: number; totalBytes: number }> {
  const output = await run("df", ["-k", DATA_VOLUME]);
  const dataLine = output.split("\n").find((line) => line.trim().endsWith(DATA_VOLUME));
  const fields = dataLine?.trim().split(/\s+/);
  // df -k row: filesystem, 1024-blocks, used, available, capacity, iused, ifree, %iused, mount
  const totalKb = fields ? Number(fields[1]) : NaN;
  const availableKb = fields ? Number(fields[3]) : NaN;
  if (!Number.isFinite(totalKb) || !Number.isFinite(availableKb) || totalKb <= 0) {
    throw new Error("unexpected df output");
  }
  // used = total - available so shared APFS container space (snapshots, purgeable)
  // counts as full, matching what the OS will actually let the user write.
  const usedKb = totalKb - availableKb;
  return {
    percent: clampPercent((usedKb / totalKb) * 100),
    usedBytes: usedKb * 1024,
    totalBytes: totalKb * 1024,
  };
}

// --- GPU: IOAccelerator performance statistics ---------------------------------

async function sampleGpuPercent(): Promise<number | undefined> {
  try {
    const output = await run("ioreg", ["-r", "-d", "1", "-w", "0", "-c", "IOAccelerator"]);
    const match = output.match(/"Device Utilization %"=(\d+)/);
    if (!match) return undefined;
    return clampPercent(Number(match[1]));
  } catch {
    return undefined;
  }
}

// --- Top RAM apps: aggregate ps rss by owning .app bundle ------------------------

// Cheap in-memory icon cache; safe to lose on reload (icons are recomputed).
const iconCache = new Map<string, string | undefined>();

function appBundleFromCommand(command: string): { bundlePath: string; name: string } | undefined {
  // Outermost .app owns helpers, e.g. Chrome's renderer helpers roll up to Chrome.
  const match = command.match(/^(.*?\/([^/]+)\.app)\//);
  if (!match) return undefined;
  return { bundlePath: match[1], name: match[2] };
}

function displayNameFromCommand(command: string): string {
  const base = command.split("/").pop() ?? command;
  return base || command;
}

async function extractAppIcon(bundlePath: string): Promise<string | undefined> {
  if (iconCache.has(bundlePath)) return iconCache.get(bundlePath);
  let icon: string | undefined;
  try {
    let iconFile: string | undefined;
    try {
      iconFile = (
        await run("plutil", ["-extract", "CFBundleIconFile", "raw", join(bundlePath, "Contents", "Info.plist")])
      ).trim();
    } catch {
      iconFile = undefined;
    }
    if (iconFile && !iconFile.endsWith(".icns")) iconFile += ".icns";
    if (!iconFile) {
      const resources = await readdir(join(bundlePath, "Contents", "Resources"));
      iconFile = resources.find((entry) => entry.endsWith(".icns"));
    }
    if (iconFile) {
      const icnsPath = join(bundlePath, "Contents", "Resources", iconFile);
      const pngPath = join(tmpdir(), `babymenu-icon-${Date.now()}-${Math.random().toString(36).slice(2)}.png`);
      try {
        await run("sips", ["-s", "format", "png", "-Z", "64", icnsPath, "--out", pngPath]);
        const png = await readFile(pngPath);
        icon = `data:image/png;base64,${png.toString("base64")}`;
      } finally {
        await unlink(pngPath).catch(() => {});
      }
    }
  } catch {
    icon = undefined;
  }
  iconCache.set(bundlePath, icon);
  return icon;
}

async function getTopRamApps(_input: unknown, _context: BabyMenuServerContext): Promise<RamAppsResult> {
  try {
    const output = await run("ps", ["-axm", "-o", "rss=,comm="]);
    const totals = new Map<string, { name: string; bundlePath?: string; bytes: number }>();
    for (const line of output.split("\n")) {
      const match = line.match(/^\s*(\d+)\s+(.+)$/);
      if (!match) continue;
      const bytes = Number(match[1]) * 1024; // ps rss is reported in KiB
      const command = match[2].trim();
      const app = appBundleFromCommand(command);
      const key = app ? app.bundlePath : command;
      const entry = totals.get(key);
      if (entry) {
        entry.bytes += bytes;
      } else {
        totals.set(key, {
          name: app ? app.name : displayNameFromCommand(command),
          bundlePath: app?.bundlePath,
          bytes,
        });
      }
    }

    const top = [...totals.values()].sort((a, b) => b.bytes - a.bytes).slice(0, 3);
    const apps: RamApp[] = await Promise.all(
      top.map(async (entry) => ({
        name: entry.name,
        memoryBytes: entry.bytes,
        iconDataUrl: entry.bundlePath ? await extractAppIcon(entry.bundlePath) : undefined,
      })),
    );
    return { ok: true, data: { apps, sampledAt: new Date().toISOString() } };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : "failed to list top ram apps" };
  }
}

// --- action ---------------------------------------------------------------------

async function getSample(_input: unknown, context: BabyMenuServerContext): Promise<SampleResult> {
  try {
    const [ram, disk, gpuPercent] = await Promise.all([sampleRam(), sampleDisk(), sampleGpuPercent()]);
    const cpuPercent = sampleCpuPercent(context.db);
    return {
      ok: true,
      data: {
        cpuPercent,
        gpuPercent,
        ramPercent: ram.percent,
        ramUsedBytes: ram.usedBytes,
        ramTotalBytes: ram.totalBytes,
        diskPercent: disk.percent,
        diskUsedBytes: disk.usedBytes,
        diskTotalBytes: disk.totalBytes,
        sampledAt: new Date().toISOString(),
      },
    };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : "failed to sample system usage" };
  }
}

export const actions = {
  getSample,
  getTopRamApps,
};
