#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/nvim-stable-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
command -v nvim >/dev/null 2>&1 || { printf 'missing test dependency: nvim\n' >&2; exit 1; }

cat >"$TMP_ROOT/check.lua" <<'LUA'
local directory = os.getenv("TEST_PLUGIN_DIR")
local expected = {
  ["NeogitOrg/neogit"] = true,
  ["lewis6991/gitsigns.nvim"] = true,
  ["windwp/nvim-autopairs"] = true,
  ["MeanderingProgrammer/render-markdown.nvim"] = true,
  ["folke/snacks.nvim"] = true,
  ["stevearc/oil.nvim"] = true,
  ["folke/which-key.nvim"] = true,
  ["rose-pine/neovim"] = true,
}
local seen = {}
for _, file in ipairs({ "editing.lua", "git.lua", "markdown.lua", "navigation.lua", "ui.lua" }) do
  for _, spec in ipairs(dofile(directory .. "/" .. file)) do
    local name = spec[1]
    if expected[name] then
      assert(spec.version == "*", name .. " does not select the latest stable SemVer release")
      seen[name] = true
    end
  end
end
for name in pairs(expected) do
  assert(seen[name], name .. " was omitted from the loaded plugin specs")
end
LUA

TEST_PLUGIN_DIR="$ROOT/config/nvim/lua/plugins" nvim -u NONE -i NONE --headless \
  -c "luafile $TMP_ROOT/check.lua" -c 'qa!'
printf 'ok - loaded Neovim plugin specs select stable SemVer\n'
