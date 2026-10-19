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

[neovide-logo]: ./original%20icon/neovide.svg

[chris-bouchard]: https://github.com/chrisbouchard
[jason-long]: https://twitter.com/jasonlong
[neovim]: https://neovim.io/
[rust-logo]: https://github.com/rust-lang/rust-artwork/tree/master/logo
[rust-media-guide]: https://www.rust-lang.org/policies/media-guide

[cc-by-4.0]: https://creativecommons.org/licenses/by/4.0/
[cc-by-3.0]: https://creativecommons.org/licenses/by/3.0/

## Original icon archive

[original icon](<original icon/README.md>) preserves the upstream Neovide PNG,
ICO, and SVG files with their provenance and license references. Active icon
paths in this directory contain this fork's Liquid Glass adaptation. The
`.desktop` launcher and installer background are separate assets, not original
icon variants.

## Custom Liquid Glass icon

This fork's icon family is a Liquid Glass adaptation by Ysrae1 of
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

The visible glass surface reduces the material's apparent saturation. The
calibrated settings in [icon-color-compensation.json](icon-color-compensation.json)
precompensate the material so the final Icon Composer render stays closer to the
original colors. Run `swift macos-builder/compensate-icon.swift --prepare` to
regenerate `Neovide.icon/Assets/original-material-compensated.png` and select it
for the original-material layer. The script always reads the preserved
`original-material.png`; never replace that original with the compensated PNG or
apply compensation repeatedly to an output. Other Icon Composer layer settings,
including the visible glass surface, remain editable and are retained.
The current HSV saturation gain is 1.17, calibrated against the unchanged
material with design generation 27. Changing the glass strength or source colors
requires a new comparison after native rendering; this is not a universal gain.

`neovide-1024.png` is the static macOS fallback. Regenerate it with
`macos-builder/export-static-icon`: the script prepares color compensation,
compiles the layered source into a temporary app with the same `actool` path
as the real application, and renders its icon through macOS IconServices.
This preserves the system's material, continuous corners, margins and shadow.
An independent flat `ictool` export does not reproduce that final appearance.
The layered icon uses the same compensated material as this static fallback;
the preserved original material remains unchanged. The static PNG then receives
the user-approved `staticBrightnessGain` of 1.025 for the white installer
background. This bounded 1–1.05 RGB gain preserves alpha and the system shadow;
it does not change native `Assets.car` rendering or the material's separate
1.17 saturation gain. All static variants and the Sketch background use that
slightly brighter PNG, so they are intentionally not exact native-icon pixels.

Do not reuse the old Sketch base shadow or subtract its rounded mask: that
geometry differs from Icon Composer's continuous corners and creates a detached
second outline. Do not shrink the already-normalized system render or add a
second outside shadow. Icon Composer retains the editable material and layers;
the application keeps its compiled layered icon under AppKit's control instead
of replacing it with a flattened image when it starts.

The shared `neovide-16x16.png`, `neovide-32x32.png`, `neovide-48x48.png`, and
`neovide-256x256.png`, Windows `neovide.ico`, and shared `neovide.svg` are generated
by `swift macos-builder/export-icon-variants.swift` from the same compensated
native render as `neovide-1024.png`. The ICO contains multiple image sizes. The SVG wraps that
rendered PNG so it preserves the glass material; it is not editable vector
artwork. Edit `Neovide.icon` and regenerate the variants instead. The upstream
vector remains available in `original icon/neovide.svg`.

`macos-builder/make-icns` generates the legacy ICNS and the retina DMG background
TIFF from the PNG sources. Regeneration never overwrites the `original icon`
archive or the preserved material inside `Neovide.icon`.

The installer background uses the same adapted icon. Its editable Sketch source
is [Neovide Liquid Glass Installer.sketch](<dmg-background/Neovide Liquid Glass Installer.sketch>),
with a PDF copy in [dmg-background/source.pdf](dmg-background/source.pdf).
Export the background at 650 × 450 and 1300 × 900 to the existing
`neovide-dmg-background.png` and `neovide-dmg-background@2x.png` paths before
running `macos-builder/make-icns`. The DMG keeps the existing drag-to-Applications
installation flow.

Save and close Icon Composer and editable Sketch documents before updating them; reopen them after
the export to view the refreshed embedded images. After regenerating the static icon, run
`python3 macos-builder/update-installer-icon.py assets/neovide-1024.png` to update
the two embedded icon references in the editable Sketch document. Export its
`neovide-dmg-background` group to both PNG sizes and `dmg-background/source.pdf`;
then run the same helper with `assets/neovide-dmg-background@2x.png` as its second
argument to refresh the document's cached background image. The helper validates
image sizes and layer identities and replaces the archive atomically. Its
`--sketch PATH` option targets a specific document.

For the complete sequence, run `macos-builder/export-static-artwork`, followed by
`macos-builder/make-icns`. The first command performs compensation, native icon export,
PNG/ICO/SVG variant generation, Sketch panel replacement, both background PNG exports, PDF export and cache refresh in
order. To synchronize the designer's original project at the same time:

```bash
NEOVIDE_SKETCH_SOURCE="$HOME/Documents/icon-builder/Neovide-macOS-Icon/source/Neovide.sketch" \
  macos-builder/export-static-artwork
```

The repository and selected external Sketch documents receive the same icon;
each background cache is rendered from its own document. Their layout, text,
other design layers and visibility are not copied over one another. Packaged
PNG/PDF assets come from the repository installer document.

The `neovide-update` maintenance entry calls both commands before Rust
compilation and packaging, after copying the selected custom assets. On this
machine it also synchronizes the original project above when present. Set
`NEOVIDE_SKETCH_SOURCE` to another document, or an empty value to disable that
additional synchronization. Keep `icon-color-compensation.json` and the complete
`Neovide.icon` source together in the selected custom-assets directory, including
the preserved original material; old flattened PNGs cannot replace this step.
Keep the `original icon` archive alongside those custom assets as well; the
updater copies it for provenance and restores the checkout's assets when done.

