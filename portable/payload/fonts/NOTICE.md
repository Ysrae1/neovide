# Bundled default fonts

Maintained by Codex, 2026-10-19. Font files are copied unchanged.

- FiraCode Nerd Font Mono: six weights (Light, Regular, Retina, Medium,
  SemiBold, Bold), from Nerd Fonts v3.3.0, Fira Code 6.002 (upstream release
  README calls this 6.2). Copyright 2014-2021 The Fira Code Project Authors
  (https://github.com/tonsky/FiraCode). Nerd Fonts copyright (c) 2014 Ryan L
  McIntyre. The original Fira Code and Nerd Fonts license texts, the release
  README, the pinned Nerd Fonts license audit, and license texts shipped
  alongside its icon sources are included in licenses/.
- Noto Sans Mono CJK SC: Regular and Bold, version 2.004. Copyright
  2014-2021 Adobe (http://www.adobe.com/), as recorded in both original font
  name tables. SIL Open Font License 1.1; see licenses/NotoSansCJK-LICENSE.txt.

Policy: install FiraCode Nerd Font Mono on macOS, Windows and Linux. macOS
retains its system PingFang SC fallback; Apple font files are not bundled.
Windows and Linux use the bundled Noto Sans Mono CJK SC fallback. No fonts
are registered or installed by merely building this package.

Sources are fixed to Nerd Fonts v3.3.0 (commit
e2dc2203202ed148ceb76d2c3100216170e94297) and Noto CJK Sans2.004 (commit
523d033d6cb47f4a80c58a35753646f5c3608a78). fonts.json records original source
URLs and SHA-256 hashes. The Nerd Fonts archive SHA-256 matches the existing
portable/manifest.json pin; the archive itself is not bundled.

The upstream Nerd Fonts license audit is reproduced unchanged. Its Font
Logos entry says "Unlicensed"; the original Font Logos 1.3.0 release instead
includes The Unlicense. The Nerd Fonts glyph source matches that official
release byte-for-byte. See licenses/FontLogos-LICENSE.txt,
licenses/FontLogos-README.md, and licenses/FontLogos-provenance.json for the
original text, trademark note, and fixed source/hash evidence. This
collection does not assert a new complete audit of the application's other
third-party dependencies. Original icon trademarks and rights remain with
their respective owners.
