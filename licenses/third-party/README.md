# Dependency notice sources

Maintained by Codex, 2026-10-19. `manifest.json` and `texts/` are the reviewed
source corpus used by `scripts/generate-third-party-notices.py`. Each original
text is named by its SHA-256 digest. The source URL, crate archive checksum,
upstream revision and original filename remain in the index. No license text
or copyright year has been invented to fill an upstream omission.

The index covers all 447 registry packages in the current `Cargo.lock`,
including dependencies for other platforms, optional features, tests and build
tools. This deliberately includes more than one platform executable links.
The two local workspace crates use the repository's root MIT license, which
`macos-builder/copy-notices` includes separately. This is not a binary inventory,
and does not purport to license operating-system libraries, external Neovim
plugins or the Rust compiler/toolchain.

Native coverage includes Skia source tag `m153-0.101.2`, immutable commit
`61e7ca4e99062cdd0ab69445d5963fb3365778f6`, selected by the locked
`skia-bindings 0.153.3`, and **all 13** `third_party/externals` revisions in that
source's `DEPS`. Thus notices include Brotli, D3D12MemoryAllocator, Expat,
FreeType, HarfBuzz, ICU, libjpeg-turbo, libpng, libwebp,
VulkanMemoryAllocator, SPIRV-Cross, Wuffs and zlib. Skia's in-tree Vulkan,
ETC1 and wrapper notices and the skcms copyright/source are also retained.
Some are unused on a particular platform. This conservative scope avoids
mistaking the binary archive's `LICENSE_SKIA` (only the Skia BSD terms) for
all of its native third-party licenses.

The libjpeg-turbo IJG README, FreeType FTL and optional GPL text, BDF/PCF
notices and gzip/zlib header, and ICU's aggregate third-party license are
included as original texts. FreeType is used under the FreeType License
option: portions of this software are copyright The FreeType Project
(https://freetype.org), all rights reserved. The included GPL alternative is
not the license selected for Neovide. libjpeg-turbo includes software based
in part on the work of the Independent JPEG Group.

Most Rust notices come from the checksum-verified crate archives. Workspace
packages that omit a root license inherit their original repository's license
at the revision recorded in `.cargo_vcs_info.json`. The shared winapi GNU
package licenses are pinned to the official winapi-rs 0.3.9 repository
revision; their archives omit VCS metadata. `typed-path 0.10.0` omits license
texts in both its archive and release commit, so the same MIT/Apache terms
later supplied by its official repository are included at a pinned revision;
its published metadata already declares those terms. CESU-8 explicitly adopts
the Rust copyright and Apache/MIT terms in its README; the original Rust
copyright notice and the full Apache-2.0 terms are both included.

## Remaining upstream gap

`dispatch 0.2.0` declares MIT and names Sam Sheldon as author in `Cargo.toml`,
but its published archive and official source repository contain no license
or copyright notice. The index records this rather than converting an author
name into a guessed copyright notice. Ordinary development packaging includes
this limitation prominently. `--check --require-complete` fails until the
upstream notice is obtained or the dependency is replaced through a separate,
reviewed dependency change. Consequently this work closes the missing notice
**collection and packaging mechanism**, but does not claim complete upstream
license compliance.

## Reproduction

```sh
# Offline validation of lockfile coverage, original hashes and native DEPS:
python3 scripts/generate-third-party-notices.py --check
# Deterministic standalone notice (also validates before writing):
python3 scripts/generate-third-party-notices.py --output target/dependency-notices.txt
# Re-fetch pinned originals, check hashes and restore the identical corpus:
python3 scripts/generate-third-party-notices.py --refresh --check
# Strict check for a complete-license release:
python3 scripts/generate-third-party-notices.py --check --require-complete
```

`--refresh` uses only the recorded URLs and hashes. It does not resolve new
versions, upgrade dependencies or write the user's global Cargo cache. A
changed lockfile intentionally fails until its new notice sources have been
reviewed. The rendered text and source index are copied into App Resources
before signing, so both accompany the app when it is placed in a DMG.
