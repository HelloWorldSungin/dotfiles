import React, { useState, useMemo } from "react";
import type { BabyMenuLayoutProps } from "@babymenu/contracts";
import { DotfileCheatsheetView } from "./dotfile-cheatsheet/components";

interface VimCmd {
  key: string;
  desc: string;
  cat: string;
}

const CHEATSHEETS: VimCmd[] = [
  // Movement
  { key: "gg", desc: "Jump to first line of file", cat: "Movement" },
  { key: "G", desc: "Jump to end of file", cat: "Movement" },
  { key: "0", desc: "Move to start of line", cat: "Movement" },
  { key: "$", desc: "Move to end of line", cat: "Movement" },
  { key: "w", desc: "Jump forward to next word", cat: "Movement" },
  { key: "b", desc: "Jump backward to word", cat: "Movement" },
  { key: "e", desc: "Jump to end of word", cat: "Movement" },
  { key: "{ / }", desc: "Jump paragraph prev / next", cat: "Movement" },
  { key: "zz", desc: "Center view on cursor", cat: "Movement" },
  { key: "Ctrl + d", desc: "Scroll half page down", cat: "Movement" },
  { key: "Ctrl + u", desc: "Scroll half page up", cat: "Movement" },

  // Editing
  { key: "i / a", desc: "Insert before / Append after cursor", cat: "Editing" },
  { key: "I / A", desc: "Insert at line start / end", cat: "Editing" },
  { key: "o / O", desc: "Open new line below / above", cat: "Editing" },
  { key: "r / R", desc: "Replace single char / Enter replace mode", cat: "Editing" },
  { key: "cc / C", desc: "Change line / Change to end of line", cat: "Editing" },
  { key: "ciw", desc: "Change inner word", cat: "Editing" },
  { key: "u / Ctrl+r", desc: "Undo / Redo change", cat: "Editing" },
  { key: ".", desc: "Repeat last editing action", cat: "Editing" },

  // Clipboard
  { key: "yy / Y", desc: "Yank (copy) line", cat: "Clipboard" },
  { key: "p / P", desc: "Paste after / before cursor", cat: "Clipboard" },
  { key: "dd / D", desc: "Delete (cut) line / to end of line", cat: "Clipboard" },
  { key: "dw / x", desc: "Delete word / single character", cat: "Clipboard" },

  // Search & Replace
  { key: "/pattern", desc: "Search forward for pattern", cat: "Search" },
  { key: "?pattern", desc: "Search backward for pattern", cat: "Search" },
  { key: "n / N", desc: "Next / previous search result", cat: "Search" },
  { key: ":%s/old/new/g", desc: "Substitute all old with new in file", cat: "Search" },

  // Advanced & Modes
  { key: "v / V / Ctrl+v", desc: "Visual mode: Char / Line / Block", cat: "Advanced" },
  { key: "qa / q / @a", desc: "Record macro to 'a' / Stop / Play 'a'", cat: "Advanced" },
  { key: ":wq / :q!", desc: "Save & quit / Quit without saving", cat: "Advanced" }
];

function CheatsheetPage() {
  const [filter, setFilter] = useState("");
  const [activeCategory, setActiveCategory] = useState<string>("All");
  const [copiedKey, setCopiedKey] = useState<string | null>(null);

  const categories = ["All", "Movement", "Editing", "Clipboard", "Search", "Advanced"];

  const filtered = useMemo(() => {
    return CHEATSHEETS.filter((item) => {
      const matchesCategory = activeCategory === "All" || item.cat === activeCategory;
      if (!matchesCategory) return false;

      if (!filter.trim()) return true;
      const q = filter.toLowerCase();
      return (
        item.key.toLowerCase().includes(q) ||
        item.desc.toLowerCase().includes(q) ||
        item.cat.toLowerCase().includes(q)
      );
    });
  }, [filter, activeCategory]);

  const grouped = useMemo(() => {
    const map: Record<string, VimCmd[]> = {};
    filtered.forEach((item) => {
      if (!map[item.cat]) map[item.cat] = [];
      map[item.cat].push(item);
    });
    return map;
  }, [filtered]);

  const copyShortcut = (key: string) => {
    navigator.clipboard.writeText(key).catch(() => {});
    setCopiedKey(key);
    setTimeout(() => setCopiedKey(null), 1200);
  };

  return (
    <div className="flex flex-col gap-3.5 w-full h-[520px] select-none">
      {/* Header Controls: Filter Tabs & Search Bar */}
      <div className="flex flex-col gap-2.5 border-b border-line-faint pb-3 shrink-0">
        <div className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-1.5 overflow-x-auto py-0.5">
            {categories.map((cat) => (
              <button
                key={cat}
                type="button"
                onClick={() => setActiveCategory(cat)}
                className={`px-2.5 py-1 text-xxs font-semibold uppercase tracking-caps rounded-md transition-all border cursor-pointer shrink-0 ${
                  activeCategory === cat
                    ? "bg-signal-live/15 border-signal-live/40 text-signal-live font-bold"
                    : "bg-ink-soft/5 border-transparent text-ink-muted hover:bg-ink-strong"
                }`}
              >
                {cat}
              </button>
            ))}
          </div>
          <span className="text-[10px] font-mono text-ink-muted shrink-0">
            {filtered.length} / {CHEATSHEETS.length}
          </span>
        </div>

        {/* Search Bar */}
        <div className="relative flex items-center w-full">
          <input
            type="text"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            placeholder="Type to filter Neovim shortcuts (e.g. 'yank', 'scroll', 'gg')..."
            className="w-full bg-ink-soft/10 border border-line hover:border-line-strong focus:border-signal-live focus:outline-none rounded-md py-1.5 pl-3 pr-14 text-xs font-medium text-ink-strong"
          />
          {filter && (
            <button
              type="button"
              onClick={() => setFilter("")}
              className="absolute right-2 text-xs text-ink-muted hover:text-ink-strong px-1.5 cursor-pointer font-semibold"
            >
              Clear
            </button>
          )}
        </div>
      </div>

      {/* Main Command List grouped by Category Section Headings */}
      <div className="flex-1 overflow-y-auto pr-1 flex flex-col gap-4">
        {Object.keys(grouped).length === 0 ? (
          <div className="flex flex-col items-center justify-center h-48 text-center gap-2">
            <span className="text-2xl">🔍</span>
            <span className="text-xs text-ink-muted font-medium">No matching shortcuts found</span>
            <button
              type="button"
              onClick={() => {
                setFilter("");
                setActiveCategory("All");
              }}
              className="text-xs text-signal-live hover:underline cursor-pointer font-semibold mt-1"
            >
              Reset filters
            </button>
          </div>
        ) : (
          Object.entries(grouped).map(([category, items]) => (
            <div key={category} className="flex flex-col gap-2">
              {/* Section Line Heading */}
              <div className="flex items-center justify-between border-b border-line-faint/50 pb-1">
                <span className="text-xs font-bold uppercase tracking-caps text-signal-live flex items-center gap-1.5">
                  ⚡ {category}
                </span>
                <span className="text-[10px] font-mono text-ink-muted">
                  {items.length} shortcut{items.length !== 1 ? "s" : ""}
                </span>
              </div>

              {/* Items Grid */}
              <div className="grid grid-cols-2 gap-2.5">
                {items.map((item, idx) => (
                  <div
                    key={idx}
                    onClick={() => copyShortcut(item.key)}
                    className="flex items-center justify-between border border-line-faint hover:border-signal-live/40 bg-ink-soft/5 hover:bg-ink-soft/10 p-2.5 rounded-md transition-all cursor-pointer group"
                  >
                    <div className="flex flex-col gap-0.5 pr-2 overflow-hidden">
                      <span className="text-xs font-semibold text-ink-strong group-hover:text-signal-live transition-colors truncate">
                        {item.desc}
                      </span>
                      <span className="text-[9px] uppercase tracking-caps text-ink-muted font-medium">
                        {item.cat}
                      </span>
                    </div>
                    <button
                      type="button"
                      className="px-2 py-1 text-xs font-mono font-bold rounded bg-ink-soft/10 border border-line-faint text-signal-live shrink-0 cursor-pointer"
                    >
                      {copiedKey === item.key ? "copied!" : item.key}
                    </button>
                  </div>
                ))}
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}

export default function Layout({ widgets, renderWidget }: BabyMenuLayoutProps) {
  const [currentPage, setCurrentPage] = useState<"quota" | "hardware" | "nvim" | "dotfiles">("quota");

  // Quota Page Widgets: github-status + all LLM quota widgets (excluding kimi-code-quota)
  const quotaWidgets = useMemo(() => {
    const list = widgets.filter(
      (widget) => (widget.id.includes("quota") && widget.id !== "kimi-code-quota") || widget.id === "github-status"
    );
    list.sort((a, b) => {
      if (a.id === "github-status") return -1;
      if (b.id === "github-status") return 1;
      return a.id.localeCompare(b.id);
    });
    return list;
  }, [widgets]);

  // Hardware Page Widgets: arknode-load, system-usage, and other non-quota/non-cheatsheet widgets
  const hardwareWidgets = useMemo(() => {
    return widgets.filter(
      (widget) =>
        !widget.id.includes("quota") &&
        widget.id !== "github-status" &&
        widget.id !== "nvim-cheatsheet" &&
        widget.id !== "dotfile-cheatsheet"
    );
  }, [widgets]);

  return (
    <div className="flex flex-col w-[840px] gap-3.5 p-3.5 bg-background text-ink min-h-[580px] justify-between">
      {/* Global Tabbed Navbar */}
      <div className="flex items-center justify-between border-b border-line-faint pb-2 mb-1.5 select-none shrink-0">
        <span className="text-[10px] font-bold uppercase tracking-caps text-ink-label flex items-center gap-1.5">
          🍼 baby menu
        </span>
        <div className="flex gap-2">
          <button
            type="button"
            onClick={() => setCurrentPage("quota")}
            className={`px-3 py-1 text-xxs font-semibold uppercase tracking-caps rounded-md transition-all duration-200 border cursor-pointer ${
              currentPage === "quota"
                ? "bg-signal-live/15 border-signal-live/40 text-signal-live font-bold"
                : "bg-ink-soft/5 border-transparent text-ink-label hover:bg-ink-soft/10 hover:text-ink-strong"
            }`}
          >
            📊 quota
          </button>
          <button
            type="button"
            onClick={() => setCurrentPage("hardware")}
            className={`px-3 py-1 text-xxs font-semibold uppercase tracking-caps rounded-md transition-all duration-200 border cursor-pointer ${
              currentPage === "hardware"
                ? "bg-signal-live/15 border-signal-live/40 text-signal-live font-bold"
                : "bg-ink-soft/5 border-transparent text-ink-label hover:bg-ink-soft/10 hover:text-ink-strong"
            }`}
          >
            💻 hardware
          </button>
          <button
            type="button"
            onClick={() => setCurrentPage("nvim")}
            className={`px-3 py-1 text-xxs font-semibold uppercase tracking-caps rounded-md transition-all duration-200 border cursor-pointer ${
              currentPage === "nvim"
                ? "bg-signal-live/15 border-signal-live/40 text-signal-live font-bold"
                : "bg-ink-soft/5 border-transparent text-ink-label hover:bg-ink-soft/10 hover:text-ink-strong"
            }`}
          >
            ⚡ nvim
          </button>
          <button
            type="button"
            onClick={() => setCurrentPage("dotfiles")}
            className={`px-3 py-1 text-xxs font-semibold uppercase tracking-caps rounded-md transition-all duration-200 border cursor-pointer ${
              currentPage === "dotfiles"
                ? "bg-signal-live/15 border-signal-live/40 text-signal-live font-bold"
                : "bg-ink-soft/5 border-transparent text-ink-label hover:bg-ink-soft/10 hover:text-ink-strong"
            }`}
          >
            🛠️ dotfiles
          </button>
        </div>
      </div>

      {/* Main Pages Content Switcher */}
      <div className="flex-1">
        {currentPage === "quota" ? (
          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-3">
              {quotaWidgets.slice(0, Math.ceil(quotaWidgets.length / 2)).map((widget) => (
                <div key={widget.id}>{renderWidget(widget.id)}</div>
              ))}
            </div>
            <div className="flex flex-col gap-3">
              {quotaWidgets.slice(Math.ceil(quotaWidgets.length / 2)).map((widget) => (
                <div key={widget.id}>{renderWidget(widget.id)}</div>
              ))}
            </div>
          </div>
        ) : currentPage === "hardware" ? (
          <div className="flex flex-col gap-3 max-w-2xl mx-auto">
            {hardwareWidgets.map((widget) => (
              <div key={widget.id}>{renderWidget(widget.id)}</div>
            ))}
          </div>
        ) : currentPage === "nvim" ? (
          <CheatsheetPage />
        ) : (
          <DotfileCheatsheetView />
        )}
      </div>
    </div>
  );
}
