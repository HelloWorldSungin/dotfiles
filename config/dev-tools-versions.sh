#!/usr/bin/env bash
# Exact toolchain release record. This file is sourced by trusted scripts in
# this repository. Keep every value a literal: no commands or environment reads.
# shellcheck disable=SC2034 # Public manifest fields are consumed by multiple callers.

TOOLCHAIN_VERIFIED_AT=2026-09-09

NIX_INSTALLER_VERSION=3.22.3
NIX_INSTALLER_SCRIPT_URL=https://install.determinate.systems/nix/tag/v3.22.3
NIX_INSTALLER_SCRIPT_SHA256=7178e5ed86c64a86f48983ac459219d78df11a31cc03145f6f81ce058d0fd4f0
NIXPKGS_CHANNEL=26.05
NIXPKGS_REV=93108a538f079596c9a16c72cf03e9322782b6dd
HOME_MANAGER_CHANNEL=26.05
HOME_MANAGER_REV=fd0956c99c41ae3c13a73a638f1f7e963aebc4ab

ANTIGRAVITY_VERSION=1.1.28
CURSOR_AGENT_OBSERVED_VERSION=2026.09.08-6caf4ff
CURSOR_INSTALLER_URL=https://cursor.com/install
CURSOR_INSTALLER_SHA256=8513e9f949576d7ced2a2a582252626cc86235437c2749bf93c886f1d5fdb203
HERDR_LATEST_MANIFEST_URL=https://herdr.dev/latest.json

TREEHOUSE_VERSION=2.3.0
NO_MISTAKES_VERSION=1.70.1
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
  'nix-installer-action|DeterminateSystems/nix-installer-action|v22|ef8a148080ab6020fd15196c2084a2eea5ff2d25'
)

# name|command|package|version|registry-integrity|guarded-apply|stable-channel
NPM_TOOL_PINS=(
  'claude|claude|@anthropic-ai/claude-code|2.1.236|sha512-sz+7GLMhFcwkN2tZHJIXGgon/g/29WMMV5UNYog9sl4OvdX5q3evM1mcXVQnasP4obP6ueItECMCpSk1MPhTDg==|no|stable'
  'codex|codex|@openai/codex|0.153.4|sha512-wbHDmit7S/YvBGVX1DQmk13xtWblZ2cApeJ/pB7xDZ10Cna+DZc5ij7f0F4OxdsXN4FW1oLT48OpogUI1+8Y2w==|no|default'
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
  'no-mistakes|no-mistakes|kunchenguid/no-mistakes|1.70.1|exact-archive|attended-only'
  'herdr|herdr|herdrdev/herdr|0.9.0|exact-binary|attended-only'
  'gbrain|gbrain|garrytan/gbrain|0.48.5.0|external-owner|attended-only'
)

# platform|treehouse-sha256|no-mistakes-sha256|herdr-sha256
RELEASE_SHA256_PINS=(
  'darwin-amd64|349afcc13c2beb20d846eb560a11b30e1a5cab8e2dfb22988a36aa7f213b5881|1e28bd7c21b9f855ff246739f8e0673bce839a7adff4c08ea8f5f440514f512f|d0c920b2a126a74809fa1491411c9a097a44786cac9c2ca51b818a995581cf16'
  'darwin-arm64|1cb09bcfa830b4eec5e54beeaa71589adb9c5d828573dda0f5150e2d80cf13d5|ee13b3dd29ca5d603fba9f04f94921c60770641d15216d7310782ceb78edf20b|32b53df09872628059c789a69f02a6b8e29e14ddf26711421f3463f70c1aef17'
  'linux-amd64|94fd2b2c20c35aac1ddc2941317890ad82c9916f5ccecbac4a50cda783eed10f|9edc3a5a97c7124b23f35d8cfa8b77976bbf6657067b36a33e3ed6670e26866b|4fa1a01158dd8043da92d31b270780b0dcc10603038d9b61cac4d81ab63fb71f'
  'linux-arm64|408589ba72b58d5e942071ed863a83fd96566cfd1e514945daa59defde528bbb|b1e011700b0f600fcb67f19f1e9e667b5075f9b5ea82807b771c7c117292e8dd|9c8db20fb7e7427b138d5367113f1621ffd319f2f65d6f009e2594029115f0d2'
)

# platform|publisher asset URL|publisher SHA-512
ANTIGRAVITY_ASSET_PINS=(
  'linux-amd64|https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.28-5576113066475520/linux-x64/cli_linux_x64.tar.gz|a855c623426fe901088bfe2b4d559b01f5b479a7c5ec0e41acfe129d4fe7deee9fbd9057072cc8e8c19ed65474cafa4f1d10fcdc14fbb85f82f20c3ec94295d4'
  'linux-arm64|https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.28-5576113066475520/linux-arm/cli_linux_arm64.tar.gz|2cc17c2a2dfe5c7d2f8088ac16ccfef270933c7844c3c717b3e4f4f94873f865ebddc5943508cbe54b4976c0f9dc478ca71b8c26b8c08d6758d9508788235530'
  'darwin-amd64|https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.28-5576113066475520/darwin-x64/cli_mac_x64.tar.gz|b6fcfaebfb8c868426dc792db4db38d1068a84e5c9aee09f46d041da06ac3a91c5956d7c5f974d3e4e67142da4732c114d7eab4fb198e3a86206d8bdb291fe9f'
  'darwin-arm64|https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.28-5576113066475520/darwin-arm/cli_mac_arm64.tar.gz|84a3bb980b0d967649e66932b04365a578a55609dea9572349a07b114067216447c1fc2f0ff55940fb6657309da665bd3af4fe8aa16af7886e131243b684087f'
)

# package|version-command|version. Nixpkgs 26.05 at NIXPKGS_REV is the
# authoritative stable source. Runtime inputs of repository-owned wrappers are
# included so the inventory covers everything Home Manager materializes.
NIX_PACKAGE_PINS=(
  'gh|gh|2.100.0' 'lazygit|lazygit|0.61.1' 'nodejs_22|node|22.23.2' 'uv|uv|0.11.21'
  'bats|bats|1.12.0' 'ripgrep|rg|15.1.0' 'fd|fd|10.4.2' 'fzf|fzf|0.72.0'
  'jq|jq|1.8.2' 'tree|tree|2.3.2' 'htop|htop|3.5.1' 'unzip|unzip|6.0'
  'neovim|nvim|0.12.4' 'zsh|zsh|5.9.1' 'starship|starship|1.25.1' 'tea|tea|0.14.0'
  'chromium|chromium|152.0.7977.82' 'ghdl|ghdl|6.0.0' 'gtkwave|gtkwave|3.3.127'
  'coreutils|timeout|9.11' 'curl|curl|8.21.0' 'gawk|gawk|5.4.1' 'git|git|2.54.0'
  'gnugrep|grep|3.12' 'gnused|sed|4.10' 'diffutils|diff|3.12'
  'gnutar|tar|1.35' 'gzip|gzip|1.14'
)

# lock-name|repository|stable-policy|recorded-release-or-ref|commit
# "head" is used only when the upstream has no release feed.
NEOVIM_PLUGIN_PINS=(
  'codewindow.nvim|gorbit99/codewindow.nvim|head|HEAD|a8e175043ce3baaa89e0a6b5171bcd920aab3dad'
  'diffview.nvim|sindrets/diffview.nvim|head|HEAD|4516612fe98ff56ae0415a259ff6361a89419b0a'
  'gitsigns.nvim|lewis6991/gitsigns.nvim|release|v2.1.0|a462f416e2ce4744531c6256252dee99a7d34a83'
  'lazy.nvim|folke/lazy.nvim|release|v11.17.5|85c7ff3711b730b4030d03144f6db6375044ae82'
  'neogit|NeogitOrg/neogit|release|v2.0.0|43fa47fb61773b0d90a78ebc2521ea8faaeebd86'
  'nvim-treesitter|nvim-treesitter/nvim-treesitter|head|HEAD|5cb0114e6242625db56dd6440e945ed1ece10bc7'
  'nvim-autopairs|windwp/nvim-autopairs|release|0.10.0|23320e75953ac82e559c610bec5a90d9c6dfa743'
  'oil.nvim|stevearc/oil.nvim|release|v2.16.0|17c0a8faaf48298a0c0cfb0d757c0eaee4ff7a32'
  'plenary.nvim|nvim-lua/plenary.nvim|head|HEAD|74b06c6c75e4eeb3108ec01852001636d85a932b'
  'render-markdown.nvim|MeanderingProgrammer/render-markdown.nvim|release|v8.13.0|f422cb5c6855f150e2ddcfaf44e7157b98b34f6a'
  'rose-pine|rose-pine/neovim|release|v3.0.2|f01eac6eedf6197509dde8b66de0263207ee1877'
  'snacks.nvim|folke/snacks.nvim|release|v2.31.0|e6fd58c82f2f3fcddd3fe81703d47d6d48fc7b9f'
  'vim-visual-multi|mg979/vim-visual-multi|head|HEAD|a6975e7c1ee157615bbc80fc25e4392f71c344d4'
  'which-key.nvim|folke/which-key.nvim|release|v3.17.0|fcbf4eea17cb299c02557d576f0d568878e354a4'
)
