import { execFile } from "node:child_process";
import type { BabyMenuServerContext, BabyMenuBackgroundTask, BabyMenuDatabase } from "@babymenu/contracts";

// Legacy empty default that made the widget look blank. Prefer the authenticated
 // gh login instead, and migrate any stored copy of this value automatically.
const LEGACY_DEFAULT_USERNAME = "sunginkim";

type GithubDay = { date: string; level: number };

type GithubData = {
  name?: string;
  totalContributions: number;
  currentStreak: number;
  stars: number;
  publicRepos: number;
  days: GithubDay[];
};

function initDb(db: BabyMenuDatabase) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS github_status_settings (
      key TEXT PRIMARY KEY,
      value TEXT
    );
  `);
  db.exec(`
    CREATE TABLE IF NOT EXISTS github_status_data (
      username TEXT PRIMARY KEY,
      name TEXT,
      total_contributions INTEGER,
      current_streak INTEGER,
      stars INTEGER,
      public_repos INTEGER,
      days_json TEXT,
      refreshed_at TEXT
    );
  `);
}

function run(command: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(command, args, { timeout: 8000, maxBuffer: 1024 * 1024 }, (error, stdout) => {
      if (error) reject(error);
      else resolve(stdout.toString());
    });
  });
}

async function detectGithubLogin(): Promise<string | undefined> {
  try {
    const login = (await run("gh", ["api", "user", "--jq", ".login"])).trim();
    return login || undefined;
  } catch {
    return undefined;
  }
}

async function resolveUsername(db: BabyMenuDatabase): Promise<string> {
  initDb(db);
  const row = db.get<{ value: string }>("SELECT value FROM github_status_settings WHERE key = 'username'");
  const saved = row?.value?.trim();
  if (saved && saved.toLowerCase() !== LEGACY_DEFAULT_USERNAME) return saved;

  const detected = await detectGithubLogin();
  const username = detected || saved || LEGACY_DEFAULT_USERNAME;
  if (username !== saved) {
    db.run("INSERT OR REPLACE INTO github_status_settings (key, value) VALUES ('username', ?)", [username]);
  }
  return username;
}

function parseContributionDays(html: string): GithubDay[] {
  const days: GithubDay[] = [];
  // Attribute order can vary; match data-date/data-level regardless of order.
  const regex =
    /<td\b[^>]*(?:data-date="(\d{4}-\d{2}-\d{2})"[^>]*data-level="(\d)"|data-level="(\d)"[^>]*data-date="(\d{4}-\d{2}-\d{2})")[^>]*>/g;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(html)) !== null) {
    const date = match[1] ?? match[4];
    const level = Number(match[2] ?? match[3]);
    if (!date || !Number.isFinite(level)) continue;
    days.push({ date, level });
  }
  days.sort((a, b) => a.date.localeCompare(b.date));
  return days;
}

function parseTotalContributions(html: string, days: GithubDay[]): number {
  const totalMatch =
    html.match(/([\d,]+)\s+contributions\s+in\s+the\s+last\s+year/i) ||
    html.match(/([\d,]+)\s+contributions\s+in\s+\d{4}/i);
  if (totalMatch) return Number(totalMatch[1].replace(/,/g, ""));
  // Fallback when the heading wraps across tags: count active days as a lower bound signal.
  return days.reduce((sum, day) => sum + (day.level > 0 ? 1 : 0), 0);
}

function currentStreakFrom(days: GithubDay[]): number {
  if (days.length === 0) return 0;
  const reversed = [...days].reverse();
  const todayStr = new Date().toISOString().slice(0, 10);
  const yesterdayStr = new Date(Date.now() - 86_400_000).toISOString().slice(0, 10);

  let startIndex = -1;
  for (let i = 0; i < reversed.length; i++) {
    if (reversed[i].date === todayStr || reversed[i].date === yesterdayStr) {
      startIndex = i;
      break;
    }
  }
  if (startIndex === -1) return 0;

  let streak = 0;
  for (let i = startIndex; i < reversed.length; i++) {
    if (reversed[i].level > 0) {
      streak += 1;
      continue;
    }
    // Today with no activity yet does not break yesterday's streak.
    if (i === startIndex && reversed[i].date === todayStr) continue;
    break;
  }
  return streak;
}

async function fetchGithubData(username: string): Promise<GithubData> {
  const contribRes = await fetch(`https://github.com/users/${encodeURIComponent(username)}/contributions`, {
    headers: { "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" },
  });
  if (!contribRes.ok) throw new Error(`Failed to fetch GitHub contributions page: ${contribRes.status}`);
  const html = await contribRes.text();
  const days = parseContributionDays(html);
  if (days.length === 0) throw new Error("GitHub contribution calendar unavailable");

  const totalContributions = parseTotalContributions(html, days);
  const currentStreak = currentStreakFrom(days);

  let name = username;
  let publicRepos = 0;
  let stars = 0;
  try {
    const userRes = await fetch(`https://api.github.com/users/${encodeURIComponent(username)}`, {
      headers: { "User-Agent": "baby-menu-widget", Accept: "application/vnd.github+json" },
    });
    if (userRes.ok) {
      const user = (await userRes.json()) as { name?: string; login?: string; public_repos?: number };
      name = user.name || user.login || username;
      publicRepos = typeof user.public_repos === "number" ? user.public_repos : 0;
    }
  } catch {
    // Profile is optional; keep contribution data.
  }

  try {
    const reposRes = await fetch(
      `https://api.github.com/users/${encodeURIComponent(username)}/repos?per_page=100&type=owner`,
      { headers: { "User-Agent": "baby-menu-widget", Accept: "application/vnd.github+json" } },
    );
    if (reposRes.ok) {
      const repos = (await reposRes.json()) as Array<{ stargazers_count?: number }>;
      if (Array.isArray(repos)) {
        stars = repos.reduce((sum, repo) => sum + (repo.stargazers_count || 0), 0);
      }
    }
  } catch {
    // Stars are optional.
  }

  return { name, totalContributions, currentStreak, stars, publicRepos, days };
}

function persistData(
  db: BabyMenuDatabase,
  username: string,
  data: GithubData,
  refreshedAt: string,
) {
  db.run(
    `INSERT OR REPLACE INTO github_status_data
     (username, name, total_contributions, current_streak, stars, public_repos, days_json, refreshed_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      username,
      data.name,
      data.totalContributions,
      data.currentStreak,
      data.stars,
      data.publicRepos,
      JSON.stringify(data.days),
      refreshedAt,
    ],
  );
}

function snapshotFromRow(username: string, row: Record<string, unknown>) {
  return {
    username,
    name: row.name as string | undefined,
    totalContributions: Number(row.total_contributions) || 0,
    currentStreak: Number(row.current_streak) || 0,
    stars: Number(row.stars) || 0,
    publicRepos: Number(row.public_repos) || 0,
    days: JSON.parse(String(row.days_json || "[]")) as GithubDay[],
    refreshedAt: String(row.refreshed_at || ""),
    stale: Date.now() - new Date(String(row.refreshed_at)).getTime() > 10 * 60 * 1000,
  };
}

export const background: BabyMenuBackgroundTask = {
  intervalMs: 5 * 60 * 1000,
  runOnStart: true,
  run: async (context) => {
    const username = await resolveUsername(context.db);
    try {
      const data = await fetchGithubData(username);
      persistData(context.db, username, data, new Date().toISOString());
    } catch {
      // Keep last-good row; the widget will show it as stale on the next read.
    }
  },
};

export const actions = {
  getContributions: async (_input: unknown, context: BabyMenuServerContext) => {
    const username = await resolveUsername(context.db);
    try {
      const row = context.db.get<Record<string, unknown>>(
        "SELECT * FROM github_status_data WHERE username = ?",
        [username],
      );
      if (row) {
        return { ok: true, data: snapshotFromRow(username, row) };
      }

      const data = await fetchGithubData(username);
      const refreshedAt = new Date().toISOString();
      persistData(context.db, username, data, refreshedAt);
      return {
        ok: true,
        data: {
          username,
          name: data.name,
          totalContributions: data.totalContributions,
          currentStreak: data.currentStreak,
          stars: data.stars,
          publicRepos: data.publicRepos,
          days: data.days,
          refreshedAt,
          stale: false,
        },
      };
    } catch (err) {
      return {
        ok: false,
        error: err instanceof Error ? err.message : "Failed to load GitHub activity",
      };
    }
  },

  saveUsername: async (input: { username?: string }, context: BabyMenuServerContext) => {
    initDb(context.db);
    const username = String(input?.username ?? "").trim();
    if (!username) return { ok: false, error: "Username cannot be empty" };

    context.db.run("INSERT OR REPLACE INTO github_status_settings (key, value) VALUES ('username', ?)", [
      username,
    ]);

    try {
      const data = await fetchGithubData(username);
      persistData(context.db, username, data, new Date().toISOString());
    } catch {
      // Ignore initial fetch error; next refresh/background run will retry.
    }

    return { ok: true };
  },

  getUsername: async (_input: unknown, context: BabyMenuServerContext) => {
    const username = await resolveUsername(context.db);
    return { ok: true, username };
  },
};
