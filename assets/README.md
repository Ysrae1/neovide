# Neovide Assets

This directory contains assets shared under various open licenses.

## Neovide Logo

The [Neovide logo][neovide-logo] was created by [Chris
Bouchard][chris-bouchard], and is shared under the [Creative Commons
Attribution v4.0 license (CC-BY)][cc-by-4.0].

Our logo contains a modified version of the Rust logo&nbsp;&mdash; namely the
outer gear ring. The [Rust logo][rust-logo] is &copy; Mozilla. It is licensed
under the [Creative Commons Attribution v4.0 license (CC-BY)][cc-by-4.0], and
is used according to [Rust's trademark policy][rust-media-guide].

Our logo also contains a modified version of the Neovim logo, with the bottom
portion obscured by the gear ring. The [Neovim][neovim] logo is &copy; [Jason
Long][jason-long]. It is licensed under the [Creative Commons Attribution 3.0
Unported License][cc-by-3.0].

[neovide-logo]: ./neovide.svg

[chris-bouchard]: https://github.com/chrisbouchard
[jason-long]: https://twitter.com/jasonlong
[neovim]: https://neovim.io/
[rust-logo]: https://github.com/rust-lang/rust-artwork/tree/master/logo
[rust-media-guide]: https://www.rust-lang.org/policies/media-guide

[cc-by-4.0]: https://creativecommons.org/licenses/by/4.0/
[cc-by-3.0]: https://creativecommons.org/licenses/by/3.0/

## Custom macOS Liquid Glass icon

This fork's macOS icon is a Liquid Glass adaptation by Ysrae1 of
[Marc Oliver Orth's Neovide macOS icon](https://github.com/marc2o/Neovide-macOS-Icon).
The original icon's MIT license and attribution are included in
[Icon-LICENSE.txt](Icon-LICENSE.txt) and [Icon-Attribution.txt](Icon-Attribution.txt).
The underlying Neovide, Rust, and Neovim logo attributions above still apply.

[Neovide.icon](Neovide.icon) is the native Icon Composer source. It preserves the
original Sketch colors, highlights, and relief in `original-material.png`, with a
separate editable glass surface in `glass-surface.svg`. The original material's
complex Sketch effects are rendered into the PNG; those effects are not separate
Icon Composer layers. Both Default and Dark appearances retain the white base;
there is no alternate dark-background design.

`neovide-1024.png` is the static macOS fallback with the original proportions and
outer shadow. `macos-builder/make-icns` generates the legacy ICNS and the retina
DMG background from the PNG sources. The shared SVG, Windows ICO, and small PNG
icons retain the upstream design.

The installer background uses the same adapted icon. Its editable Sketch source
is [Neovide Liquid Glass Installer.sketch](<dmg-background/Neovide Liquid Glass Installer.sketch>),
with a PDF copy in [dmg-background/source.pdf](dmg-background/source.pdf).
Export the background at 650 × 450 and 1300 × 900 to the existing
`neovide-dmg-background.png` and `neovide-dmg-background@2x.png` paths before
running `macos-builder/make-icns`. The DMG keeps the existing drag-to-Applications
installation flow.

