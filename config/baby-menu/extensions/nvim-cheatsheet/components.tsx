import React, { useState, useMemo, useEffect, useRef } from "react";
import { CHEATSHEET_DATA, VimCommand } from "./data";

// Helper to copy text to clipboard and show temporary status
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
      className={`relative inline-flex items-center justify-center min-w-[54px] px-2 py-0.75 text-xs font-mono font-bold rounded border transition-all duration-200 cursor-pointer select-none ${
        copied
          ? "bg-signal-live/15 border-signal-live text-signal-live scale-[0.96]"
          : "bg-ink-soft/5 border-line hover:bg-ink-soft/10 hover:border-signal-live/50 hover:text-signal-live"
      }`}
    >
      <span>{copied ? "copied!" : cmd}</span>
    </button>
  );
}

// Interactive Directional Compass representing Neovim motions
function DirectionalCompass({ onKeySelect }: { onKeySelect: (key: string) => void }) {
  // Arrow directions keys matching the user's desktop wallpaper structure
  const upwardKeys = [
    { key: "gg", desc: "first line" },
    { key: "H", desc: "cursor to top of screen" },
    { key: "{", desc: "start of paragraph" },
    { key: "(", desc: "start of sentence" },
    { key: "#", desc: "find word under cursor backward" },
    { key: "N", desc: "search opposite direction" },
    { key: "M", desc: "cursor to middle of screen" }
  ];

  const downwardKeys = [
    { key: "n", desc: "search same direction" },
    { key: "*", desc: "find word under cursor forward" },
    { key: ")", desc: "end of sentence" },
    { key: "}", desc: "end of paragraph" },
    { key: "L", desc: "cursor to bottom of screen" },
    { key: "#G", desc: "go to line #" },
    { key: "G", desc: "end of file" }
  ];

  const backwardKeys = [
    { key: "0", desc: "hard start of line" },
    { key: "^", desc: "soft start of line" },
    { key: "<", desc: "shift left" },
    { key: ",", desc: "repeat find backward" },
    { key: "F", desc: "inclusive find backward" },
    { key: "T", desc: "find backward till" },
    { key: "ge", desc: "word end backward" },
    { key: "b", desc: "word backward" }
  ];

  const forwardKeys = [
    { key: "w", desc: "word forward" },
    { key: "e", desc: "word end forward" },
    { key: "t", desc: "find forward till" },
    { key: "f", desc: "inclusive find forward" },
    { key: ";", desc: "repeat find forward" },
    { key: ">", desc: "shift right" },
    { key: "%", desc: "matching bracket" },
    { key: "$", desc: "hard end of line" }
  ];

  const renderKeyPill = (item: { key: string; desc: string }) => (
    <button
      key={item.key}
      type="button"
      onClick={() => onKeySelect(item.key)}
      title={item.desc}
      className="px-1.5 py-0.5 text-xxs font-mono rounded bg-ink-soft/5 hover:bg-signal-live/15 hover:text-signal-live border border-transparent hover:border-signal-live/30 transition-all text-ink cursor-pointer truncate max-w-[65px] text-center"
    >
      {item.key}
    </button>
  );

  return (
    <div className="flex flex-col gap-2 rounded-lg border border-line-faint bg-ink-soft/5 p-3 select-none">
      <div className="flex items-center gap-1.5 text-xxs uppercase tracking-caps text-ink-label border-b border-line-faint pb-1.5 mb-1">
        <span className="text-signal-live font-semibold">🧭 motion compass</span>
        <span className="text-xxs text-ink-muted lowercase">(click key to highlight/filter)</span>
      </div>

      {/* Main Grid mapping the Center Neovim Logo + 4-directional stems */}
      <div className="grid grid-cols-3 gap-2 py-1 items-center justify-center">
        
        {/* Top-Left Corner: Empty */}
        <div></div>

        {/* UPWARD STEM */}
        <div className="flex flex-col items-center gap-1 bg-ink-soft/5 rounded p-1 border border-line-faint/10">
          <span className="text-[9px] uppercase tracking-caps text-ink-muted">▲ upward</span>
          <div className="flex flex-wrap gap-1 justify-center max-w-[100px]">
            {upwardKeys.slice(0, 4).map(renderKeyPill)}
          </div>
          <div className="flex flex-wrap gap-1 justify-center max-w-[100px]">
            {upwardKeys.slice(4).map(renderKeyPill)}
          </div>
        </div>

        {/* Top-Right Corner: Empty */}
        <div></div>

        {/* BACKWARD STEM (LEFT) */}
        <div className="flex flex-col items-center gap-1 bg-ink-soft/5 rounded p-1 border border-line-faint/10">
          <span className="text-[9px] uppercase tracking-caps text-ink-muted">◀ backward</span>
          <div className="grid grid-cols-2 gap-1 max-w-[120px]">
            {backwardKeys.map(renderKeyPill)}
          </div>
        </div>

        {/* CENTER LOGO */}
        <div className="flex flex-col items-center justify-center py-4 bg-gradient-to-br from-signal-live/5 to-accent/5 rounded-full border border-signal-live/20 w-16 h-16 mx-auto shadow-inner">
          <svg className="w-7 h-7 text-signal-live" viewBox="0 0 24 24" fill="currentColor">
            <path d="M21.5,12.7c-0.1,0-0.1-0.1-0.2-0.1l-10-8.8C11,3.6,10.6,3.5,10.2,3.7C9.8,3.9,9.5,4.3,9.5,4.8v6l-5.3,3.7c-0.2,0.1-0.3,0.4-0.3,0.6v5.8c0,0.4,0.3,0.8,0.7,0.9c0.4,0.1,0.8-0.1,1-0.4l8.2-11.2c0.2-0.2,0.5-0.3,0.8-0.2c0.3,0.1,0.5,0.3,0.5,0.6v11.8c0,0.4,0.3,0.8,0.7,0.9c0.4,0.1,0.8-0.1,1-0.4l5.3-7.5C21.8,14.6,21.9,13.6,21.5,12.7z" />
          </svg>
          <span className="text-[9px] font-bold font-mono tracking-wide text-ink-strong mt-0.5">NVIM</span>
        </div>

        {/* FORWARD STEM (RIGHT) */}
        <div className="flex flex-col items-center gap-1 bg-ink-soft/5 rounded p-1 border border-line-faint/10">
          <span className="text-[9px] uppercase tracking-caps text-ink-muted">forward ▶</span>
          <div className="grid grid-cols-2 gap-1 max-w-[120px]">
            {forwardKeys.map(renderKeyPill)}
          </div>
        </div>

        {/* Bottom-Left Corner: Empty */}
        <div></div>

        {/* DOWNWARD STEM */}
        <div className="flex flex-col items-center gap-1 bg-ink-soft/5 rounded p-1 border border-line-faint/10">
          <span className="text-[9px] uppercase tracking-caps text-ink-muted">▼ downward</span>
          <div className="flex flex-wrap gap-1 justify-center max-w-[100px]">
            {downwardKeys.slice(0, 4).map(renderKeyPill)}
          </div>
          <div className="flex flex-wrap gap-1 justify-center max-w-[100px]">
            {downwardKeys.slice(4).map(renderKeyPill)}
          </div>
        </div>

        {/* Bottom-Right Corner: Empty */}
        <div></div>
      </div>
    </div>
  );
}

// Vim Grammar card explaining the syntax formula
function VimGrammarCard() {
  return (
    <div className="flex flex-col gap-3 rounded-lg border border-line-faint bg-ink-soft/5 p-4 shadow-sm">
      <div className="flex items-center gap-1.5 text-xxs uppercase tracking-caps text-ink-label border-b border-line-faint pb-1.5">
        <span className="text-signal-live font-semibold">🧠 how to think in vim</span>
      </div>

      <div className="flex flex-col gap-2">
        <p className="text-xs text-ink leading-relaxed">
          Vim is a language. Don't memorize keys; write sentences using this structure:
        </p>

        <div className="flex items-center justify-between bg-ink-soft/10 border border-line/20 rounded px-3 py-2 text-center my-1 select-none font-mono">
          <div className="flex flex-col">
            <span className="text-signal-danger font-bold text-sm">verb</span>
            <span className="text-[9px] text-ink-muted uppercase">action</span>
          </div>
          <span className="text-ink-muted">+</span>
          <div className="flex flex-col">
            <span className="text-signal-warn font-bold text-sm">modifier</span>
            <span className="text-[9px] text-ink-muted uppercase">scope</span>
          </div>
          <span className="text-ink-muted">+</span>
          <div className="flex flex-col">
            <span className="text-accent font-bold text-sm">noun</span>
            <span className="text-[9px] text-ink-muted uppercase">target</span>
          </div>
        </div>

        <div className="flex flex-col gap-1.5 mt-1 border-t border-line-faint/10 pt-2 text-xs">
          <div className="flex justify-between">
            <span className="font-semibold text-ink-strong">Verbs:</span>
            <span className="text-ink-muted font-mono"><span className="text-signal-danger">c</span> (change) · <span className="text-signal-danger">d</span> (delete) · <span className="text-signal-danger">y</span> (copy/yank)</span>
          </div>
          <div className="flex justify-between">
            <span className="font-semibold text-ink-strong">Modifiers:</span>
            <span className="text-ink-muted font-mono"><span className="text-signal-warn">i</span> (inside) · <span className="text-signal-warn">a</span> (around) · <span className="text-signal-warn">t</span> (till) · <span className="text-signal-warn">f</span> (find)</span>
          </div>
          <div className="flex justify-between">
            <span className="font-semibold text-ink-strong">Nouns:</span>
            <span className="text-ink-muted font-mono"><span className="text-accent">w</span> (word) · <span className="text-accent">s</span> (sentence) · <span className="text-accent">p</span> (paragraph) · <span className="text-accent">b</span> (bracket)</span>
          </div>
        </div>

        <div className="flex flex-col gap-1.5 mt-2 bg-ink-soft/10 rounded px-2.5 py-2 border border-line-faint/5 font-mono text-[11px] text-ink">
          <div className="flex items-center gap-2">
            <span className="text-signal-live font-bold">diw</span>
            <span className="text-ink-muted">→ delete inside word</span>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-signal-live font-bold">ci(</span>
            <span className="text-ink-muted">→ change inside parentheses</span>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-signal-live font-bold">yap</span>
            <span className="text-ink-muted">→ copy around paragraph</span>
          </div>
        </div>
      </div>
    </div>
  );
}

export function NvimCheatsheetView() {
  const [search, setSearch] = useState("");
  const [activeTab, setActiveTab] = useState<"all" | "movement" | "editing" | "clipboard" | "search_replace" | "advanced">("all");
  const searchInputRef = useRef<HTMLInputElement>(null);

  // Setup keyboard shortcut ⌘F to focus search input
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "f") {
        e.preventDefault();
        searchInputRef.current?.focus();
      }
      if (e.key === "Escape" && search !== "") {
        setSearch("");
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [search]);

  // Filter commands by search term or selected tab
  const filteredCommands = useMemo(() => {
    let list = CHEATSHEET_DATA;

    if (search.trim() !== "") {
      const query = search.toLowerCase().trim();
      return list.filter(
        (cmd) =>
          cmd.key.toLowerCase().includes(query) ||
          cmd.desc.toLowerCase().includes(query) ||
          cmd.keywords.some((kw) => kw.includes(query)) ||
          (cmd.subcategory && cmd.subcategory.toLowerCase().includes(query))
      );
    }

    if (activeTab !== "all") {
      list = list.filter((cmd) => cmd.category === activeTab);
    }

    return list;
  }, [search, activeTab]);

  // Group commands by subcategory when not searching
  const groupedCommands = useMemo(() => {
    const groups: Record<string, VimCommand[]> = {};
    filteredCommands.forEach((cmd) => {
      const sub = cmd.subcategory || "Other";
      if (!groups[sub]) groups[sub] = [];
      groups[sub].push(cmd);
    });
    return groups;
  }, [filteredCommands]);

  const handleKeySelect = (key: string) => {
    setSearch(key);
    searchInputRef.current?.focus();
  };

  return (
    <div className="flex flex-col gap-4 w-full h-[540px] overflow-hidden select-none">
      
      {/* Search Header */}
      <div className="flex items-center gap-3 shrink-0 border-b border-line-faint/15 pb-3">
        <div className="relative flex-1">
          <span className="absolute left-3 top-2.5 text-xs text-ink-muted">🔍</span>
          <input
            ref={searchInputRef}
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search commands or descriptors (e.g. 'yank', 'gg', 'scroll')... Press Esc to clear."
            className="w-full bg-ink-soft/10 border border-line hover:border-line-strong focus:border-signal-live focus:outline-none rounded-md py-2 pl-9 pr-10 text-xs font-medium text-ink-strong transition-all"
          />
          {search && (
            <button
              onClick={() => setSearch("")}
              className="absolute right-3 top-2.5 text-ink-faint hover:text-ink-strong text-xs font-semibold"
            >
              ✕
            </button>
          )}
        </div>
      </div>

      {/* Tabs list (Category selector) */}
      <div className="flex gap-1.5 shrink-0 overflow-x-auto pb-1 scrollbar-none select-none">
        {(["all", "movement", "editing", "clipboard", "search_replace", "advanced"] as const).map((tab) => {
          const isActive = activeTab === tab && !search;
          const label = tab === "search_replace" ? "Search & Replace" : tab;
          return (
            <button
              key={tab}
              type="button"
              onClick={() => {
                setSearch("");
                setActiveTab(tab);
              }}
              className={`px-3 py-1 text-xxs font-semibold uppercase tracking-caps rounded-md transition-all duration-200 border cursor-pointer ${
                isActive
                  ? "bg-signal-live/15 border-signal-live/40 text-signal-live"
                  : "bg-ink-soft/5 border-transparent text-ink-label hover:bg-ink-soft/10 hover:text-ink-strong"
              }`}
            >
              {label}
            </button>
          );
        })}
        <button
          type="button"
          onClick={() => {
            setSearch("");
            setActiveTab("all");
            // Jump directly to grammar tab logic
            const container = document.getElementById("cheatsheet-scroll-container");
            if (container) {
              container.scrollTo({ top: container.scrollHeight, behavior: "smooth" });
            }
          }}
          className="px-3 py-1 text-xxs font-semibold uppercase tracking-caps rounded-md bg-ink-soft/5 hover:bg-ink-soft/10 border border-transparent text-ink-label hover:text-ink-strong transition-all cursor-pointer ml-auto"
        >
          🧠 grammar
        </button>
      </div>

      {/* Main scrollable body */}
      <div
        id="cheatsheet-scroll-container"
        className="flex-1 overflow-y-auto pr-1 pb-4 scrollbar-thin"
      >
        {search.trim() !== "" ? (
          /* Search results layout */
          <div className="flex flex-col gap-2">
            <div className="text-xxs uppercase tracking-caps text-ink-label border-b border-line-faint pb-1.5">
              found {filteredCommands.length} command{filteredCommands.length !== 1 && "s"} matching "{search}"
            </div>
            
            {filteredCommands.length > 0 ? (
              <div className="grid grid-cols-2 gap-2">
                {filteredCommands.map((cmd) => (
                  <div
                    key={`${cmd.category}-${cmd.key}`}
                    onClick={() => handleKeySelect(cmd.key)}
                    className="flex items-center justify-between border border-line-faint hover:border-signal-live/30 bg-ink-soft/5 hover:bg-ink-soft/10 p-2.5 rounded-lg transition-all duration-150 group cursor-pointer"
                  >
                    <div className="flex flex-col gap-0.5 truncate pr-2">
                      <span className="text-[11px] font-semibold text-ink-strong group-hover:text-signal-live transition-colors">
                        {cmd.desc}
                      </span>
                      <span className="text-[9px] uppercase tracking-caps text-ink-faint font-mono">
                        {cmd.category.replace("_", " & ")} {cmd.subcategory ? `· ${cmd.subcategory}` : ""}
                      </span>
                    </div>
                    <CommandBadge cmd={cmd.key} />
                  </div>
                ))}
              </div>
            ) : (
              <div className="text-xs text-ink-muted text-center py-10 bg-ink-soft/5 rounded-lg border border-line-faint/5">
                No matching Neovim commands found. Try searching for "yank", "delete", "insert", or specific keys.
              </div>
            )}
          </div>
        ) : (
          /* Two-column standard layout */
          <div className="grid grid-cols-12 gap-4 items-start">
            
            {/* Left Column: Command grids (takes 7 columns) */}
            <div className="col-span-7 flex flex-col gap-4">
              {Object.entries(groupedCommands).map(([subcategory, cmds]) => (
                <div key={subcategory} className="flex flex-col gap-2">
                  <div className="flex items-center justify-between border-b border-line-faint/50 pb-1 mb-1">
                    <span className="text-xs font-bold uppercase tracking-caps text-signal-live flex items-center gap-1.5">
                      ⚡ {subcategory}
                    </span>
                    <span className="text-[10px] font-mono text-ink-muted">
                      {cmds.length}
                    </span>
                  </div>
                  <div className="flex flex-col gap-1.5">
                    {cmds.map((cmd) => (
                      <div
                        key={cmd.key}
                        className="flex items-center justify-between py-1 px-1.5 hover:bg-ink-soft/5 rounded transition-all duration-100 group"
                      >
                        <span className="text-xs text-ink-strong font-medium pr-3 line-clamp-2">
                          {cmd.desc}
                        </span>
                        <CommandBadge cmd={cmd.key} />
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>

            {/* Right Column: Interactive helpers (takes 5 columns) */}
            <div className="col-span-5 flex flex-col gap-4 sticky top-0">
              <DirectionalCompass onKeySelect={handleKeySelect} />
              <VimGrammarCard />
            </div>

          </div>
        )}
      </div>

    </div>
  );
}
