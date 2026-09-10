# Inventory disposition

All 68 scout rows are accounted for. Installed observations are separate from
repository pins. The starting packaged checker still carried the pre-PR-17
no-mistakes pin; the repository baseline for that row is already 1.72.0.

For `user-env` packages, the checker observes the command on its inherited PATH.
In both task checks, Codex's bundled `codex-path/rg` reported 15.2.0. The explicit
Nix profile `rg` reported 15.1.0, matching the locked derivation and the earlier
scout observation. Both observations are valid: the difference is PATH shadowing,
and the Nix package did not change.

| Tool | Repository pin after | Audit observation | Decision |
|---|---|---|---|
| claude | `2.1.236` | `2.1.267` | retained |
| codex | `0.154.0` | `0.153.4` | updated |
| opencode | `1.18.30` | `1.18.16` | retained |
| pi | `0.85.1` | `0.85.1` | retained |
| gnhf | `0.1.49` | `0.1.43` | retained |
| gh-axi | `0.1.35` | `0.1.34` | retained |
| tasks-axi | `0.2.5` | `0.2.5` | retained |
| quota-axi | `0.1.41` | `0.1.32` | retained |
| chrome-devtools-axi | `0.1.34` | `0.1.33` | retained |
| lavish-axi | `0.1.67` | `0.1.62` | retained |
| treehouse | `2.3.0` | `2.1.0` | retained |
| no-mistakes | `1.72.0` | `1.72.0` | retained |
| herdr | `0.9.0` | `0.8.2` | retained |
| gbrain | `0.48.5.0` | `0.46.21.0` | excluded; runtime remains 0.46.21.0 |
| antigravity | `1.2.0` | `1.1.23` | updated |
| cursor-agent | `2026.09.08-6caf4ff` | `2026.09.02-c22c1a3` | observed beta unchanged |
| firstmate | `0fe226c93efdd12a38f1c3936d758571e40111b7` | `83f4a40bff0ee86960bd7f4774a92068da56880b` | held pending upstream-sync |
| baby-menu | `65eb280ea0e05c17677f10b56afc75e91f899f65` | `unknown` | retained |
| nix-installer | `3.22.3` | `3.21.7` | retained |
| nixpkgs-input | `d58a46e3bc02d91ebe04667f8397752a749c0024` | `d58a46e3bc02d91ebe04667f8397752a749c0024` | updated |
| home-manager-input | `fd0956c99c41ae3c13a73a638f1f7e963aebc4ab` | `fd0956c99c41ae3c13a73a638f1f7e963aebc4ab` | retained |
| opencode-acp | `1.18.30` | `on-demand` | retained |
| omp-acp | `0.1.2` | `on-demand` | retained |
| claude-spend | `1.0.6` | `on-demand` | retained |
| nix:gh | `2.100.0` | `2.100.0` | retained |
| nix:lazygit | `0.61.1` | `0.61.1` | retained |
| nix:nodejs_22 | `22.23.2` | `22.23.2` | retained |
| nix:uv | `0.11.21` | `0.11.21` | retained |
| nix:bats | `1.12.0` | `1.12.0` | retained |
| nix:ripgrep | `15.1.0` | `15.2.0` (Codex PATH); `15.1.0` (Nix profile) | retained |
| nix:fd | `10.4.2` | `10.4.2` | retained |
| nix:fzf | `0.72.0` | `0.72.0` | retained |
| nix:jq | `1.8.2` | `1.8.2` | retained |
| nix:tree | `2.3.2` | `2.3.2` | retained |
| nix:htop | `3.5.1` | `3.5.1` | retained |
| nix:unzip | `6.0` | `6.0` | retained |
| nix:neovim | `0.12.4` | `0.12.4` | retained |
| nix:zsh | `5.9.1` | `5.9.1` | retained |
| nix:starship | `1.25.1` | `1.25.1` | retained |
| nix:tea | `0.14.0` | `0.14.0` | retained |
| nix:chromium | `152.0.7977.82` | `152.0.7977.82` | retained |
| nix:ghdl | `6.0.0` | `6.0.0` | retained |
| nix:gtkwave | `3.3.127` | `3.3.127` | retained |
| nix:coreutils | `9.11` | `9.11` | retained |
| nix:curl | `8.21.0` | `8.21.0` | retained |
| nix:gawk | `5.4.1` | `5.4.1` | retained |
| nix:git | `2.54.0` | `2.54.0` | retained |
| nix:gnugrep | `3.12` | `3.12` | retained |
| nix:gnused | `4.10` | `4.10` | retained |
| nix:diffutils | `3.12` | `3.12` | retained |
| nix:gnutar | `1.35` | `1.35` | retained |
| nix:gzip | `1.14` | `1.14` | retained |
| ci:actions-checkout | `3d3c42e5aac5ba805825da76410c181273ba90b1` | `on-demand` | retained |
| ci:nix-installer-action | `3138316df39ed29be04236d7ffc686fa525866aa` | `on-demand` | updated |
| nvim:codewindow.nvim | `a8e175043ce3baaa89e0a6b5171bcd920aab3dad` | `a8e175043ce3baaa89e0a6b5171bcd920aab3dad` | retained |
| nvim:diffview.nvim | `4516612fe98ff56ae0415a259ff6361a89419b0a` | `4516612fe98ff56ae0415a259ff6361a89419b0a` | retained |
| nvim:gitsigns.nvim | `a462f416e2ce4744531c6256252dee99a7d34a83` | `31d6fb2d618bca1482b9f274751ead5f03461408` | retained |
| nvim:lazy.nvim | `85c7ff3711b730b4030d03144f6db6375044ae82` | `306a05526ada86a7b30af95c5cc81ffba93fef97` | retained |
| nvim:neogit | `43fa47fb61773b0d90a78ebc2521ea8faaeebd86` | `2043096b7ae81e8350ec8cceb3e7ab08dca1dcfe` | retained |
| nvim:nvim-treesitter | `d4d59cb369da46b95699bd2200efbcffc6dadb3b` | `7248feaca45e4d944591497964bc19afa89ad1c6` | updated |
| nvim:nvim-autopairs | `23320e75953ac82e559c610bec5a90d9c6dfa743` | `7b9923abad60b903ece7c52940e1321d39eccc79` | retained |
| nvim:oil.nvim | `17c0a8faaf48298a0c0cfb0d757c0eaee4ff7a32` | `b73018b75affd13fa38e2fc94ef753b465f770d7` | retained |
| nvim:plenary.nvim | `74b06c6c75e4eeb3108ec01852001636d85a932b` | `74b06c6c75e4eeb3108ec01852001636d85a932b` | retained |
| nvim:render-markdown.nvim | `f422cb5c6855f150e2ddcfaf44e7157b98b34f6a` | `f422cb5c6855f150e2ddcfaf44e7157b98b34f6a` | retained |
| nvim:rose-pine | `f01eac6eedf6197509dde8b66de0263207ee1877` | `ff483051a47e27d84bdef47703538df1ed9f4a47` | retained |
| nvim:snacks.nvim | `e6fd58c82f2f3fcddd3fe81703d47d6d48fc7b9f` | `882c996cf28183f4d63640de0b4c02ec886d01f2` | retained |
| nvim:vim-visual-multi | `a6975e7c1ee157615bbc80fc25e4392f71c344d4` | `a6975e7c1ee157615bbc80fc25e4392f71c344d4` | retained |
| nvim:which-key.nvim | `fcbf4eea17cb299c02557d576f0d568878e354a4` | `3aab2147e74890957785941f0c1ad87d0a44c15a` | retained |
