import React, { useState, useMemo, useEffect, useRef } from "react";
import { DOTFILE_CHEATSHEET_DATA, DOTFILE_CONFIGS, DotfileCommand } from "./data";

function CommandBadge({ cmd }: { cmd: string }) {
  const [copied, setCopied] = useState(false);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, []);

  const handleCopy = async (e: React.MouseEvent) => {
    e.stopPropagation();
    try {
      await navigator.clipboard.writeText(cmd);
      setCopied(true);
      if (timerRef.current) clearTimeout(timerRef.current);
      timerRef.current = setTimeout(() => setCopied(false), 1200);
    } catch (err) {
      console.error("Failed to copy command", err);
    }
  };

  return (
    <button
      type="button"
      onClick={handleCopy}
      title="Click to copy shortcut"
      className={`relative inline-flex items-center justify-center min-w-[70px] px-2.5 py-1 text-xs font-mono font-bold rounded-md border transition-all duration-200 cursor-pointer select-none shrink-0 ${
        copied
          ? "bg-signal-live/20 border-signal-live text-signal-live scale-[0.96] shadow-sm"
          : "bg-ink-soft/10 border-line-faint hover:bg-ink-soft/20 hover:border-signal-live/50 hover:text-signal-live"
      }`}
    >
      <span>{copied ? "copied!" : cmd}</span>
    </button>
  );
}

export function DotfileCheatsheetView() {
  const [filter, setFilter] = useState("");
  const [activeCategory, setActiveCategory] = useState<string>("All");

  const categories = ["All", "WezTerm", "Herdr", "TUI Prompt", "Neovim", "Zsh"];

  const filtered = useMemo(() => {
    return DOTFILE_CHEATSHEET_DATA.filter((item) => {
      const matchesCategory = activeCategory === "All" || item.category === activeCategory;
      if (!matchesCategory) return false;

      if (!filter.trim()) return true;
      const q = filter.toLowerCase();
      return (
        item.key.toLowerCase().includes(q) ||
        item.desc.toLowerCase().includes(q) ||
        item.category.toLowerCase().includes(q) ||
        (item.subcategory && item.subcategory.toLowerCase().includes(q)) ||
        (item.config && item.config.toLowerCase().includes(q)) ||
        item.keywords.some((k) => k.toLowerCase().includes(q))
      );
    });
  }, [filter, activeCategory]);

  const grouped = useMemo(() => {
    const map: Record<string, DotfileCommand[]> = {};
    filtered.forEach((item) => {
      if (!map[item.category]) map[item.category] = [];
      map[item.category].push(item);
    });
    return map;
  }, [filtered]);

  return (
    <div className="flex flex-col gap-3 w-full h-[520px] select-none">
      {/* Header & Filter Controls */}
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
                    : "bg-ink-soft/5 border-transparent text-ink-muted hover:bg-ink-soft/10 hover:text-ink-strong"
                }`}
              >
                {cat}
              </button>
            ))}
          </div>
          <span className="text-[10px] font-mono text-ink-muted shrink-0">
            {filtered.length} / {DOTFILE_CHEATSHEET_DATA.length}
          </span>
        </div>

        {/* Search Bar */}
        <div className="relative flex items-center w-full">
          <input
            type="text"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            placeholder="Filter shortcuts (e.g. 'WezTerm', 'QuickSelect', 'detach', 'fzf', 'multi-cursor')..."
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

      {/* Main Command List grouped by category */}
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
              {/* Category Subheader */}
              <div className="flex items-center justify-between border-b border-line-faint/50 pb-1">
                <span className="text-xs font-bold uppercase tracking-caps text-signal-live flex items-center gap-1.5">
                  📁 {category}
                </span>
                {DOTFILE_CONFIGS[category as keyof typeof DOTFILE_CONFIGS] && (
                  <span className="text-[10px] font-mono text-ink-muted bg-ink-soft/5 px-2 py-0.5 rounded border border-line-faint">
                    {DOTFILE_CONFIGS[category as keyof typeof DOTFILE_CONFIGS]}
                  </span>
                )}
              </div>

              {/* Items Grid */}
              <div className="grid grid-cols-2 gap-2.5">
                {items.map((item, idx) => (
                  <div
                    key={idx}
                    className="flex items-center justify-between border border-line-faint hover:border-signal-live/40 bg-ink-soft/5 hover:bg-ink-soft/10 p-2.5 rounded-md transition-all group"
                  >
                    <div className="flex flex-col gap-0.5 pr-2 overflow-hidden">
                      <div className="flex items-center gap-1.5">
                        <span className="text-xs font-semibold text-ink-strong group-hover:text-signal-live transition-colors truncate">
                          {item.desc}
                        </span>
                        {item.mode && (
                          <span className="text-[9px] font-mono px-1 py-0.2 rounded bg-signal-live/10 text-signal-live border border-signal-live/20">
                            {item.mode}
                          </span>
                        )}
                      </div>
                      {item.subcategory && (
                        <span className="text-[9px] uppercase tracking-caps text-ink-muted font-medium">
                          {item.subcategory}
                        </span>
                      )}
                    </div>
                    <CommandBadge cmd={item.key} />
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
