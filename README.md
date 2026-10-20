# Neovide

> **Neovide Glow — personal customized fork:** adjustable native bloom and a pinned portable setup,
> based on [Neovide](https://github.com/neovide/neovide).
> [Live showcase](https://neovide-glow.windygrass17.chatgpt.site/) ·
> [Download the frozen release](https://github.com/Ysrae1/neovide/releases/tag/glow-stack-20261020-gm1) ·
> [Deployment guide](https://github.com/Ysrae1/neovide/blob/glow-preview/portable/DEPLOY.md)

> **Experimental glow branch:** this fork adds adjustable native bloom while preserving the
> full-resolution base rendering. See [GLOW.md](GLOW.md) for settings, build instructions, tested
> platforms, and how to merge future upstream updates. The upstream project is
> [neovide/neovide](https://github.com/neovide/neovide).

[![Discord](https://img.shields.io/discord/896132176091955261?style=flat&logo=discord)](https://discord.gg/SjFpZdQys6) [![Chat on Matrix](https://matrix.to/img/matrix-badge.svg)](https://matrix.to/#/#neovide:matrix.org) [![Discussions](https://img.shields.io/badge/GitHub-Discussions-green?logo=github)](https://github.com/neovide/neovide/discussions)

<img align="left" src="website/docs/assets/neovide-128x128.png">

This is a simple graphical user interface for [Neovim](https://github.com/neovim/neovim) (an
aggressively refactored and updated Vim editor). Where possible there are some graphical
improvements, but functionally it should act like the terminal UI.

To checkout all the **cool features**, **installation instructions**, **configuration settings** and
much more, head on over to [neovide.dev](https://neovide.dev).

<br>

<div align="center">
    <img src="website/docs/assets/BasicScreenCap.png" alt="Screenshot of Neovide">
    <em>Screenshot of Neovide running on Windows</em>
</div>

## Installation

Neovide requires Neovim **0.12+**

Pre-built releases for macOS, Windows and Linux are published on the
[GitHub Releases page](https://github.com/neovide/neovide/releases) and each release includes signed
installers or AppImage builds. For detailed package-manager commands, verification steps and build
from source instructions, see the [installation guide on neovide.dev](https://neovide.dev/installation.html)

## Getting help

Neovide is maintained in spare time, so please be patient when asking for support. Depending on your
question:

- Use the [issue tracker](https://github.com/neovide/neovide/issues) for reproducible bugs or crash reports.
- Open a thread in [GitHub Discussions](https://github.com/neovide/neovide/discussions) for general
  questions, tips, or feature ideas.
- Chat in real time on [Discord](https://discord.gg/SjFpZdQys6) or on
  [Matrix](https://matrix.to/#/#neovide:matrix.org) if you want help from other community members.

Discussions and chat are better suited to questions or workflow brainstorming, while the issue
tracker works best for actionable bugs.

## Supporting the Project

If you use and like Neovide, please consider
[sponsoring the project on GitHub](https://github.com/sponsors/neovide). Funding helps pay for
code-signing certificates, cross-platform hardware and the time maintainers spend supporting users.
There are tiers for individuals and teams, and one-time contributions are welcome too.

[Read more about sponsoring Neovide](https://neovide.dev/sponsor.html).

## Glow maintenance

Run `python3 tests/validate.py` for isolated headless checks of the portable configuration.
See [validation commands and platform limits](tests/VALIDATION.md),
[the GUI/configuration interface](extra/glow-protocol.md), and [current Glow status](GLOW.md).

## Credits

Neovide Glow is a personal fork that combines and adapts the work of many open-source projects.
Each component keeps its own license.

- **Neovide** — the upstream editor this fork is based on, under the [MIT license](./LICENSE).
- **Icon** — based on [Neovide-macOS-Icon](https://github.com/marc2o/Neovide-macOS-Icon) by Marc
  Oliver Orth (marc2o), [MIT](assets/Icon-LICENSE.txt). That icon carries the upstream Neovide logo
  by [Chris Bouchard](https://github.com/chrisbouchard)
  ([CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)), which contains a modified Rust logo
  (© Mozilla, CC BY 4.0, used according to the
  [Rust media guide](https://www.rust-lang.org/policies/media-guide)) and a modified Neovim logo
  (© Jason Long, [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)). Ysrae1 adapted it for
  Liquid Glass, including color compensation and installer artwork. See the
  [asset notes](assets/README.md).
- **Color scheme** — the Ayu Light/Dark palettes start from [ayu](https://github.com/dempfi/ayu) by
  Ike Ku (MIT), through the ayu themes of [NvChad Base46](https://github.com/NvChad/base46) (MIT).
  Every color was then retuned by hand.
- **Neovim configuration** — built on the [LazyVim starter](https://github.com/LazyVim/starter)
  (Apache-2.0) and [NvChad ui](https://github.com/NvChad/ui) (GPL-3.0). Plugins are installed from
  their own repositories at the commits pinned in
  [`lazy-lock.json`](portable/payload/nvim/lazy-lock.json) and keep their own licenses.
- **Notebook** — editing and execution use [Molten](https://github.com/benlubas/molten-nvim)
  (GPL-3.0) and [jupytext.nvim](https://github.com/GCBallesteros/jupytext.nvim). The static preview
  bundles [KaTeX](https://github.com/KaTeX/KaTeX) and
  [markdown-it](https://github.com/markdown-it/markdown-it), both MIT; see the
  [third-party notices](portable/payload/nvim/lua/config/media/assets/THIRD-PARTY-NOTICES.md).
- **Matrix rain** — [`cmatrix-gm`](https://github.com/Ysrae1/cmatrix-gm) adapts
  [CMatrix](https://github.com/abishekvashok/cmatrix) (GPL-3.0), with an
  [Unimatrix](https://github.com/will8211/unimatrix)-style mode and
  [Gomatrix](https://github.com/GeertJohan/gomatrix)-style streams (BSD-2-Clause). License texts
  are in [`portable/licenses`](portable/licenses).
- **File manager** — [Yazi](https://github.com/sxyazi/yazi), with the bundled ayu-dark flavor
  (MIT, © Kamal Chandra Upreti; tmTheme © Ike Ku).
- **Native image preview** — informed by fredizzimo's
  [img-support work (PR #3039)](https://github.com/neovide/neovide/pull/3039); no code was merged
  wholesale.

## License

Licensed under [MIT](./LICENSE).

## Pinned personal environment

The [portable setup](portable/README.md) contains the locked Neovim configuration, native cmatrix-gm adaptation, Mac and Windows/WSL entry points, and a [deployment guide](portable/DEPLOY.md) suitable for users or Codex. Download the [2026-10-20 snapshot](https://github.com/Ysrae1/neovide/releases/tag/glow-stack-20261020-gm1) for the self-contained Mac installer or the cross-platform ZIP. Mac installation preserves the DMG drag-to-Applications workflow. Windows runtime validation is pending. Components retain their individual licenses.
