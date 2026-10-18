# Neovide

> **Neovide Glow — personal customized fork:** adjustable native bloom and a pinned portable setup,
> based on [Neovide](https://github.com/neovide/neovide).
> [Live showcase](https://neovide-glow.windygrass17.chatgpt.site/) ·
> [Download the gm2 release](https://github.com/Ysrae1/neovide/releases/tag/glow-stack-20261017-gm2) ·
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

## Icon credits

The custom icon family is based on [Neovide-macOS-Icon](https://github.com/marc2o/Neovide-macOS-Icon)
by Marc Oliver Orth (marc2o). Ysrae1 adapted it for Liquid Glass, including color compensation and
installer artwork. See the [asset notes](assets/README.md) and the original icon's
[MIT license](assets/Icon-LICENSE.txt).

## License

Licensed under [MIT](./LICENSE).

## Pinned personal environment

The [portable setup](portable/README.md) contains the locked Neovim configuration, native cmatrix-gm adaptation, Mac and Windows/WSL entry points, and a [deployment guide](portable/DEPLOY.md) suitable for users or Codex. Download the [2026-10-17 snapshot](https://github.com/Ysrae1/neovide/releases/tag/glow-stack-20261017-gm2) for the self-contained Mac installer or the cross-platform ZIP. Mac installation preserves the DMG drag-to-Applications workflow. Windows runtime validation is pending. Components retain their individual licenses.
