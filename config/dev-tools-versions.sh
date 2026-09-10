#!/usr/bin/env bash
# Exact toolchain release record. This file is sourced by trusted scripts in
# this repository. Keep every value a literal: no commands or environment reads.
# shellcheck disable=SC2034 # Public manifest fields are consumed by multiple callers.

TOOLCHAIN_VERIFIED_AT=2026-09-10

NIX_INSTALLER_VERSION=3.22.3
NIX_INSTALLER_SCRIPT_URL=https://install.determinate.systems/nix/tag/v3.22.3
NIX_INSTALLER_SCRIPT_SHA256=7178e5ed86c64a86f48983ac459219d78df11a31cc03145f6f81ce058d0fd4f0
NIXPKGS_CHANNEL=26.05
NIXPKGS_REV=d58a46e3bc02d91ebe04667f8397752a749c0024
HOME_MANAGER_CHANNEL=26.05
HOME_MANAGER_REV=fd0956c99c41ae3c13a73a638f1f7e963aebc4ab

ANTIGRAVITY_VERSION=1.2.0
CURSOR_AGENT_OBSERVED_VERSION=2026.09.08-6caf4ff
CURSOR_INSTALLER_URL=https://cursor.com/install
CURSOR_INSTALLER_SHA256=8513e9f949576d7ced2a2a582252626cc86235437c2749bf93c886f1d5fdb203
HERDR_LATEST_MANIFEST_URL=https://herdr.dev/latest.json

TREEHOUSE_VERSION=2.3.0
NO_MISTAKES_VERSION=1.72.0
HERDR_VERSION=0.9.0

OPENCODE_ACP_VERSION=1.18.30
OMP_ACP_VERSION=0.1.2
CLAUDE_SPEND_VERSION=1.0.6

FIRSTMATE_REV=0fe226c93efdd12a38f1c3936d758571e40111b7
BABY_MENU_VERSION=0.1.24
BABY_MENU_REV=65eb280ea0e05c17677f10b56afc75e91f899f65

# name|repository|stable-release-tag|commit
CI_ACTION_PINS=(
  'actions-checkout|actions/checkout|v7.0.1|3d3c42e5aac5ba805825da76410c181273ba90b1'
  'nix-installer-action|DeterminateSystems/nix-installer-action|v23|3138316df39ed29be04236d7ffc686fa525866aa'
)

# name|command|package|version|registry-integrity|guarded-apply|stable-channel
NPM_TOOL_PINS=(
  'claude|claude|@anthropic-ai/claude-code|2.1.236|sha512-sz+7GLMhFcwkN2tZHJIXGgon/g/29WMMV5UNYog9sl4OvdX5q3evM1mcXVQnasP4obP6ueItECMCpSk1MPhTDg==|no|stable'
  'codex|codex|@openai/codex|0.154.0|sha512-FV/x1OHXYv/ifjf3mXj9ThTTAWcUZN6cGIRQRhRxkKNOPuImu1WW0c8ev1vUkE9XGH90dEnYG1tBjIkxRikg0w==|no|default'
  'opencode|opencode|opencode-ai|1.18.30|sha512-oLcOLQE4XzDKy6T5L5d1RdVJvXHXwVlD4hRF5V317JbUQorrl2EyDdGZk5kbgv675J9FXp8usg92MZbEWhh6gQ==|no|default'
  'pi|pi|@earendil-works/pi-coding-agent|0.85.1|sha512-FGRN+OHbWaefBPGaTggAdLjrIHW+s2PzLyglz/5dfLzb9of7uuXMXYC0fJIeZTw+shS32o2cuQ9jF7YSDuL/oQ==|no|default'
  'gnhf|gnhf|gnhf|0.1.49|sha512-HzvxCzLaNZ2ipN7bqkn90f0sVbp4BgHv11RDOJY9fB1HL5cAdrSIDNQvpwjtqsPLRjRoymHnyJpsz2WOynbL2g==|yes|default'
  'gh-axi|gh-axi|gh-axi|0.1.35|sha512-xxe7ui0548FJ9KF0LTQZWdfm8UYuLRsfSidSEx3Ztu1Eqrn4GMg+oJW7UReG33Wt0+2Vppwl7P6Qcll0KpymTQ==|yes|default'
  'tasks-axi|tasks-axi|tasks-axi|0.2.5|sha512-FxssEW7+MuUNHWJ7uhdGrRsBDev/Zw5NutUBHcf8r/npG6z9+NfUUIeXdcdDHrC9ixEKOqQ9Uomay2TLpDB6Eg==|yes|default'
  'quota-axi|quota-axi|quota-axi|0.1.41|sha512-PJEse+te7LteX0tfVpCGzfL8bz6MaLLejx2iClOeT+eoJU7qRMekRRibAx4Bvr4ZFqEP7SjLbJYdU+D3tp0NlA==|yes|default'
  'chrome-devtools-axi|chrome-devtools-axi|chrome-devtools-axi|0.1.34|sha512-DCLOYmUxs9mDxhv82NKLbSwjfykGRC9kHRocz/Vz45rGxX/kxUbtuvLf1Bxr17V9jINVdsJGGUXGFfnrE51/9w==|yes|default'
  'lavish-axi|lavish-axi|lavish-axi|0.1.67|sha512-7qU7tF1ShNQEQY3SMceNkIR2T1Iuy3kOvatoOgPwUW1QJuXoi+vzF5NOiDSt7xMfNaKJMNLefY856yylFxOxHg==|yes|default'
)

# name|command|owner/repo|version|install-policy|apply-policy
GITHUB_TOOL_PINS=(
  'treehouse|treehouse|kunchenguid/treehouse|2.3.0|exact-archive|report-only'
  'no-mistakes|no-mistakes|kunchenguid/no-mistakes|1.72.0|exact-archive|attended-only'
  'herdr|herdr|herdrdev/herdr|0.9.0|exact-binary|attended-only'
  'gbrain|gbrain|garrytan/gbrain|0.48.5.0|external-owner|attended-only'
)

# platform|treehouse-sha256|no-mistakes-sha256|herdr-sha256
RELEASE_SHA256_PINS=(
  'darwin-amd64|349afcc13c2beb20d846eb560a11b30e1a5cab8e2dfb22988a36aa7f213b5881|b82a873be9473670f38abe1d9a21a64877c445307d85dfd8d10dfd8d3e1f90d2|d0c920b2a126a74809fa1491411c9a097a44786cac9c2ca51b818a995581cf16'
  'darwin-arm64|1cb09bcfa830b4eec5e54beeaa71589adb9c5d828573dda0f5150e2d80cf13d5|c3a38e95e050c30ee303806f22fbdc708f945e28d6b249d8e9540de65becb5c7|32b53df09872628059c789a69f02a6b8e29e14ddf26711421f3463f70c1aef17'
  'linux-amd64|94fd2b2c20c35aac1ddc2941317890ad82c9916f5ccecbac4a50cda783eed10f|c226b69b8b8115827d2e438ea8b32eaff9b89291a1d2fddc5ef2449017b8d927|4fa1a01158dd8043da92d31b270780b0dcc10603038d9b61cac4d81ab63fb71f'
  'linux-arm64|408589ba72b58d5e942071ed863a83fd96566cfd1e514945daa59defde528bbb|92f402654bdea845ded9cebca41fd565e2ae654bb81c9ce2282e0a2610df8736|9c8db20fb7e7427b138d5367113f1621ffd319f2f65d6f009e2594029115f0d2'
)

# platform|publisher asset URL|publisher SHA-512
ANTIGRAVITY_ASSET_PINS=(
  'linux-amd64|https://storage.googleapis.com/antigravity-public/antigravity-cli/1.2.0-5210873191596032/linux-x64/cli_linux_x64.tar.gz|d190b25a04ed2a03b0587838476494ae59d0d324ee6373263cabe584352c254f9051f3689c79ac4add8817ff6eb34b11694acd77002c55e91bd1d28b6dfdae22'
  'linux-arm64|https://storage.googleapis.com/antigravity-public/antigravity-cli/1.2.0-5210873191596032/linux-arm/cli_linux_arm64.tar.gz|5ad72fba8c8e915c59c5505dc99116058352b8eba7f141d7ed220256788bada30df8b5af65c0d931ff10bbc661c0f5fe83931c58071fe3063a809bbeda7f59f9'
  'darwin-amd64|https://storage.googleapis.com/antigravity-public/antigravity-cli/1.2.0-5210873191596032/darwin-x64/cli_mac_x64.tar.gz|a69a9253add7765f826b51e080005efff9e09b303aebc4f56a08fad29396d9e4ab49f549f0dfb5b686403a5ffb62031f34d65f98da6929fa4fbeb43c64f641b9'
  'darwin-arm64|https://storage.googleapis.com/antigravity-public/antigravity-cli/1.2.0-5210873191596032/darwin-arm/cli_mac_arm64.tar.gz|7ca4c9d044adc76a1a7b0d5e73fa8b3dc0d56e9e8417f72a747e9bf9ff9783f7a57722c602c2fbb9b5bf5967e4b5568e4f62270480df499fa25ab971c8c2a886'
)

# package|version-command|version|evidence-class. Nixpkgs 26.05 at NIXPKGS_REV
# is the authoritative stable source. Runtime inputs of repository-owned wrappers
# are included so the inventory covers everything Home Manager materializes.
# The evidence class says where the installed version may be read from:
#   user-env  the package is in the user environment, so the command the operator
#             runs is the pinned one and is measured through PATH.
#   closure   the package reaches the operator only through a wrapper's own PATH,
#             so it is measured from the exact store path home/dev-tools.nix
#             generates. It is never read through PATH - that would report an
#             unrelated system build - and reports unknown when the generated
#             manifest is absent or does not bind it.
NIX_PACKAGE_PINS=(
  'gh|gh|2.100.0|user-env' 'lazygit|lazygit|0.61.1|user-env' 'nodejs_22|node|22.23.2|user-env'
  'uv|uv|0.11.21|user-env' 'bats|bats|1.12.0|user-env' 'ripgrep|rg|15.1.0|user-env'
  'fd|fd|10.4.2|user-env' 'fzf|fzf|0.72.0|user-env' 'jq|jq|1.8.2|user-env'
  'tree|tree|2.3.2|user-env' 'htop|htop|3.5.1|user-env' 'unzip|unzip|6.0|user-env'
  'neovim|nvim|0.12.4|user-env' 'zsh|zsh|5.9.1|user-env' 'starship|starship|1.25.1|user-env'
  'tea|tea|0.14.0|user-env' 'chromium|chromium|152.0.7977.82|user-env' 'ghdl|ghdl|6.0.0|user-env'
  'gtkwave|gtkwave|3.3.127|user-env' 'coreutils|timeout|9.11|closure' 'curl|curl|8.21.0|closure'
  'gawk|gawk|5.4.1|closure' 'git|git|2.54.0|user-env' 'gnugrep|grep|3.12|closure'
  'gnused|sed|4.10|closure' 'diffutils|diff|3.12|closure' 'gnutar|tar|1.35|closure'
  'gzip|gzip|1.14|closure'
)


# lock-name|repository|stable-policy|recorded-release-or-ref|commit
# "head" is used only when the upstream has no release feed.
NEOVIM_PLUGIN_PINS=(
  'codewindow.nvim|gorbit99/codewindow.nvim|head|HEAD|a8e175043ce3baaa89e0a6b5171bcd920aab3dad'
  'diffview.nvim|sindrets/diffview.nvim|head|HEAD|4516612fe98ff56ae0415a259ff6361a89419b0a'
  'gitsigns.nvim|lewis6991/gitsigns.nvim|release|v2.1.0|a462f416e2ce4744531c6256252dee99a7d34a83'
  'lazy.nvim|folke/lazy.nvim|release|v11.17.5|85c7ff3711b730b4030d03144f6db6375044ae82'
  'neogit|NeogitOrg/neogit|release|v2.0.0|43fa47fb61773b0d90a78ebc2521ea8faaeebd86'
  'nvim-treesitter|nvim-treesitter/nvim-treesitter|head|HEAD|d4d59cb369da46b95699bd2200efbcffc6dadb3b'
  'nvim-autopairs|windwp/nvim-autopairs|release|0.10.0|23320e75953ac82e559c610bec5a90d9c6dfa743'
  'oil.nvim|stevearc/oil.nvim|release|v2.16.0|17c0a8faaf48298a0c0cfb0d757c0eaee4ff7a32'
  'plenary.nvim|nvim-lua/plenary.nvim|head|HEAD|74b06c6c75e4eeb3108ec01852001636d85a932b'
  'render-markdown.nvim|MeanderingProgrammer/render-markdown.nvim|release|v8.13.0|f422cb5c6855f150e2ddcfaf44e7157b98b34f6a'
  'rose-pine|rose-pine/neovim|release|v3.0.2|f01eac6eedf6197509dde8b66de0263207ee1877'
  'snacks.nvim|folke/snacks.nvim|release|v2.31.0|e6fd58c82f2f3fcddd3fe81703d47d6d48fc7b9f'
  'vim-visual-multi|mg979/vim-visual-multi|head|HEAD|a6975e7c1ee157615bbc80fc25e4392f71c344d4'
  'which-key.nvim|folke/which-key.nvim|release|v3.17.0|fcbf4eea17cb299c02557d576f0d568878e354a4'
)
