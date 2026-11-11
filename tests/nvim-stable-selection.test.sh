#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/nvim-stable-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
command -v nvim >/dev/null 2>&1 || { printf 'missing test dependency: nvim\n' >&2; exit 1; }
command -v nix >/dev/null 2>&1 || { printf 'missing test dependency: nix\n' >&2; exit 1; }

REPO="$TMP_ROOT/lazy-remote"
mkdir -p "$REPO" "$TMP_ROOT/bin"
git -C "$REPO" init -q -b main
printf 'old stable\n' >"$REPO/release"
git -C "$REPO" add release
git -C "$REPO" -c user.email=tests@example.invalid -c user.name=tests commit -qm old-stable
git -C "$REPO" tag v1.0.0
printf 'current stable\n' >>"$REPO/release"
git -C "$REPO" -c user.email=tests@example.invalid -c user.name=tests commit -qam current-stable
STABLE_COMMIT=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" -c user.email=tests@example.invalid -c user.name=tests tag -am stable stable
git -C "$REPO" -c user.email=tests@example.invalid -c user.name=tests tag -am v2.0.0 v2.0.0
printf 'preview\n' >>"$REPO/release"
git -C "$REPO" -c user.email=tests@example.invalid -c user.name=tests commit -qam preview
git -C "$REPO" tag v3.0.0-beta.1

LAZY_SOURCE=$(nix build --no-link --print-out-paths --impure --expr \
  'let flake = builtins.getFlake (toString ./.); in (builtins.getAttr builtins.currentSystem flake.inputs.nixpkgs.legacyPackages).vimPlugins.lazy-nvim')
[ -f "$LAZY_SOURCE/lua/lazy/manage/git.lua" ] || { printf 'lazy.nvim resolver unavailable in Nix package\n' >&2; exit 1; }
cat >"$TMP_ROOT/check.lua" <<'LUA'
local source = os.getenv("TEST_LAZY_SOURCE")
package.path = source .. "/lua/?.lua;" .. source .. "/lua/?/init.lua;" .. package.path
local git = require("lazy.manage.git")
local directory = os.getenv("TEST_PLUGIN_DIR")
local repository = os.getenv("TEST_LAZY_REPO")
local stable_commit = os.getenv("TEST_STABLE_COMMIT")
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
      spec.dir = repository
      spec.branch = "main"
      spec._ = {}
      local target = git.get_target(spec)
      assert(target and target.tag == "v2.0.0", name .. " selected a prerelease or stale tag")
      assert(target.commit == stable_commit, name .. " selected the wrong commit")
      seen[name] = true
    end
  end
end
for name in pairs(expected) do
  assert(seen[name], name .. " was omitted from the loaded plugin specs")
end
LUA

TEST_LAZY_SOURCE="$LAZY_SOURCE" TEST_LAZY_REPO="$REPO" TEST_STABLE_COMMIT="$STABLE_COMMIT" \
  TEST_PLUGIN_DIR="$ROOT/config/nvim/lua/plugins" nvim -u NONE -i NONE --headless \
  -c "luafile $TMP_ROOT/check.lua" -c 'qa!'
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
printf 'ok - lazy.nvim resolves loaded plugins to stable SemVer tags\n'
