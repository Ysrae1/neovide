# Original Neovide icons

This folder preserves the unmodified green Neovide icon variants previously
stored directly in `assets/`:

- `neovide-16x16.png`, `neovide-32x32.png`, `neovide-48x48.png`,
  `neovide-256x256.png`, and `neovide-1024.png`
- `neovide.ico`
- `neovide.svg` (the original editable vector)

All seven files come byte for byte from
[neovide/neovide at commit 19c705370fda1d1cacc2ce9633fb282cb78a5898](https://github.com/neovide/neovide/tree/19c705370fda1d1cacc2ce9633fb282cb78a5898/assets).
The six smaller PNG/ICO/SVG files matched the working tree before the Liquid
Glass variants were generated. The original 1024 PNG was restored from that
same upstream commit because the active 1024 path already contained the custom
icon.

The Neovide logo was created by Chris Bouchard under CC BY 4.0 and incorporates
the Rust and Neovim logos. See the full logo attribution and license links in
[the parent assets README](../README.md#neovide-logo). Moving these files does
not change their licenses.

The active icons in the parent directory are Ysrae1's Liquid Glass adaptation
of [Marc Oliver Orth's macOS icon](https://github.com/marc2o/Neovide-macOS-Icon),
whose MIT license and attribution remain in
[Icon-LICENSE.txt](../Icon-LICENSE.txt) and
[Icon-Attribution.txt](../Icon-Attribution.txt). That macOS material source is
preserved separately as `Neovide.icon/Assets/original-material.png`; it is an
input to the color compensation process and must remain at that path.

Do not generate outputs into this archive. Generate the fork's PNG, ICO, SVG,
and macOS variants into their existing active paths in the parent directory.
