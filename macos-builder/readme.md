# Neovide Packaging for macOS

This script is designed to build (if needed) and package the Neovide application packaging it into a macOS `.app` bundle, and then creating a `.dmg` disk image for distribution.

## Prerequisites

Before running the script, ensure you have the following dependencies installed:

- [cargo](https://doc.rust-lang.org/cargo/getting-started/installation.html)
- [create-dmg](https://github.com/create-dmg/create-dmg)
- [codesign](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)

**Run the Script**:

```bash
GENERATE_BUNDLE_APP=true GENERATE_DMG=true ./macos-builder/run aarch64-apple-darwin
```

### Steps

**Set Up Release Directory**:
The script sets the `RELEASE_DIR` based on the `TARGET_ARCHITECTURE` environment variable. If `TARGET_ARCHITECTURE` is not set, it defaults to `target/release`.

```bash
RELEASE_DIR=${TARGET_ARCHITECTURE:+target/${TARGET_ARCHITECTURE}/release}
RELEASE_DIR=${RELEASE_DIR:-target/release}
```

**Build the Project**:
If the release directory does not exist, the script runs the `cargo build --release` command to build the project.

_*This is for local development purposes since you would typically build the project beforehand.*_

```bash
if [ ! -d "${RELEASE_DIR}" ]; then
  cargo build --release ${TARGET_ARCHITECTURE:+--target "${TARGET_ARCHITECTURE}"}
fi
```

**Prepare the Application Bundle**:

- Sets up directories for the `.app` bundle.
- Copies the built binary and other necessary resources into the bundle.
- Signs the application using `codesign`.

```bash
mkdir -p "${APP_BINARY_DIR}"
mkdir -p "${APP_EXTRAS_DIR}"
cp -fRp "${APP_TEMPLATE}" "${APP_DIR}"
cp -fp "${APP_BINARY}" "${APP_BINARY_DIR}"
touch -r "${APP_BINARY}" "${APP_DIR}/${APP_NAME}"
codesign --remove-signature "${APP_DIR}/${APP_NAME}"
codesign --force --deep --sign - "${APP_DIR}/${APP_NAME}"
```

**Create the Disk Image**:
Uses `create-dmg` to create a `.dmg` file for the application.

```bash
create-dmg \
  --filesystem "${DMG_FILESYSTEM}" \
  --format "${DMG_FORMAT}" \
  --volname "${DMG_VOLNAME}" \
  --volicon "${DMG_ICNS}" \
  --background "${DMG_BACKGROUND}" \
  --window-size 650 470 \
  --icon-size 80 \
  --icon Neovide.app 240 320 \
  --app-drop-link 410 320 \
  "${APP_DIR}/${DMG_NAME}" \
  "${APP_DIR}/${APP_NAME}"
```

## Notes

- Ensure all paths and filenames are correct and that the necessary files (like `Neovide.icns` and `neovide-dmg-background.tiff`) are present in their respective directories.
- The script assumes a macOS environment with the necessary tools installed.

## Native layered icon in this fork

The application remains a Rust/Cargo project. When `assets/Neovide.icon` is
present, `macos-builder/run` calls `macos-builder/make-native-icon` before signing
the generated app. The helper uses `xcrun actool` from an Xcode installation with
Icon Composer support to compile the layered source into `Assets.car` and add
its `CFBundleIconName` to the generated bundle. No Xcode project is required.
Select that Xcode installation with `xcode-select` if `actool` is unavailable.
An icon compilation failure stops packaging before signing.

The source preserves the original Sketch material as a PNG plus an independent
glass surface. `swift macos-builder/compensate-icon.swift --prepare` generates a separate compensated
material from that original and `assets/icon-color-compensation.json` before
native rendering. It selects the generated image for the original-material layer
without changing the other glass settings. Repeated builds start from the
preserved original, so saturation is not increased again on each export.
The Default and Dark appearances both keep the white base,
without a separate dark-background variation. Marc Oliver Orth's original MIT
license and the adaptation attribution are copied into the app's Resources;
see [the asset documentation](../assets/README.md) for the original logo notices
and editable artwork.

When changing the static icon, run `macos-builder/export-static-artwork` to prepare
compensation, export the icon, replace the embedded icon in the editable Sketch installer panel, and
regenerate both PNG background sizes and the PDF. It also refreshes the Sketch
document's cached background. See [assets/README.md](../assets/README.md).
Its native Core Graphics shadow follows the Icon Composer export's alpha;
never add a shadow or rounded mask from the old Sketch base.

Save and close Icon Composer and Sketch documents before running this export. Set
`NEOVIDE_SKETCH_SOURCE` to the designer's external `.sketch` project to synchronize
its embedded icon as well. Both documents retain their own design layers and
get a background cache rendered from their own installer panel; the repository
source supplies the packaged PNGs/PDF. Reopen the project after exporting.

The local `neovide-update` maintenance entry runs this pipeline after copying
custom assets and before `make-icns`, Rust compilation or packaging. Missing
tools or failed artwork exports stop the update before compilation; the existing
asset restoration and manual DMG installation flow are retained. Use
`ICON_COMPOSER_TOOL` and `SKETCH_TOOL` to select tools outside their default
application locations. `export-static-artwork --check` only checks prerequisites
and compensation inputs. `swift macos-builder/compensate-icon.swift --check ASSETS_DIR` can validate
a selected custom-assets directory without modifying it. Keep its original PNG,
compensation settings and layered `.icon` source synchronized with the chosen
design; the update cannot use only old flattened images.

`neovide-update` automatically synchronizes
`$HOME/Documents/icon-builder/Neovide-macOS-Icon/source/Neovide.sketch` when it
exists. `NEOVIDE_SKETCH_SOURCE` overrides that location; an explicitly empty value
disables the additional document update. This external source is not part of the
temporary build-asset restoration, so its refreshed icon/cache remain saved.

Before packaging changed static artwork, run `macos-builder/make-icns` to
regenerate `Neovide.icns` and the retina background TIFF from the supplied PNGs.
The generated app retains `Neovide.icns` and `CFBundleIconFile` as the legacy
fallback, and the DMG uses that ICNS as its volume icon. The existing signing
sequence, installer layout, and drag-to-Applications step remain unchanged.
The build produces an installer; it does not replace an installed app.
