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
REPO="$TMP_ROOT/lazy-remote"
mkdir -p "$REPO" "$TMP_ROOT/bin"
git -C "$REPO" init -q -b main
printf 'stable\n' >"$REPO/release"
git -C "$REPO" add release
git -C "$REPO" -c user.email=tests@example.invalid -c user.name=tests commit -qm stable
STABLE_COMMIT=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" -c user.email=tests@example.invalid -c user.name=tests tag -am stable stable
printf 'development\n' >>"$REPO/release"
git -C "$REPO" -c user.email=tests@example.invalid -c user.name=tests commit -qam development
cat >"$TMP_ROOT/bin/git" <<'SH'
#!/usr/bin/env bash
args=()
for arg in "$@"; do
  [ "$arg" = https://github.com/folke/lazy.nvim.git ] && arg="file://$TEST_LAZY_REPO"
  args+=("$arg")
done
exec "$TEST_REAL_GIT" "${args[@]}"
SH
chmod +x "$TMP_ROOT/bin/git"
cat >"$TMP_ROOT/bootstrap.lua" <<'LUA'
package.loaded["vim-config"] = {}
package.loaded["keys"] = {}
package.loaded["lazy"] = { setup = function() end }
dofile(os.getenv("TEST_NVIM_INIT"))
LUA
TEST_NVIM_INIT="$ROOT/config/nvim/init.lua" TEST_LAZY_REPO="$REPO" TEST_REAL_GIT="$(command -v git)" \
  XDG_DATA_HOME="$TMP_ROOT/data" XDG_CACHE_HOME="$TMP_ROOT/cache" PATH="$TMP_ROOT/bin:$PATH" \
  nvim -u NONE -i NONE --headless -c "luafile $TMP_ROOT/bootstrap.lua" -c 'qa!'
[ "$(git -C "$TMP_ROOT/data/nvim/lazy/lazy.nvim" rev-parse HEAD)" = "$STABLE_COMMIT" ] || {
  printf 'lazy.nvim bootstrap did not select the stable tag commit\n' >&2
  exit 1
}
printf 'ok - lazy.nvim bootstrap selects the peeled stable tag\n'
printf 'ok - loaded Neovim plugin specs select stable SemVer\n'
