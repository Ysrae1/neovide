# Windows installer language resources

`installer.iss` bundles English and Simplified Chinese. The language selector
defaults to the Windows display language on each run; `/LANG=english` and
`/LANG=chinesesimplified` select a language explicitly. All Glow-specific wizard,
directory, font and dependency messages live in its `[CustomMessages]` section.
The Start menu ` Setup` shortcut name stays stable; its description is localized.

The installer writes `en` or `zh-CN` to `{app}\glow-ui-language.txt` before
launching the dependency setup window. These ASCII bytes are valid UTF-8 without
a BOM. The launcher reads this application-local choice on later launches.
Uninstall removes only that exact generated marker, in addition to files and
shortcuts tracked by Inno Setup; user configuration and shared dependencies are
outside this cleanup. Silent installation still skips dependencies unless
`/INSTALLDEPS=1` is supplied.

## Source and license

`ChineseSimplified.isl` is an unmodified, UTF-8-with-BOM copy of Zhenghan Yang's
translation, pinned to the maintainer's revision
[`977acab5e417a7b17e3fb83fee13a3cc9394f33d`](https://github.com/kira-96/Inno-Setup-Chinese-Simplified-Translation/tree/977acab5e417a7b17e3fb83fee13a3cc9394f33d).
The current maintainer is listed on the
[official Inno Setup translations page](https://jrsoftware.org/files/istrans/).
This older revision is intentionally selected for the existing Inno Setup 6.3
build baseline; the current official translation targets newer compiler versions.

- [Pinned translation](https://raw.githubusercontent.com/kira-96/Inno-Setup-Chinese-Simplified-Translation/977acab5e417a7b17e3fb83fee13a3cc9394f33d/ChineseSimplified.isl)
  SHA-256: `454dc06a5edcc5e643b24a2270dddca5bcda326ed71cdd24a5fe15a332889674`.
- [Pinned MIT license](https://raw.githubusercontent.com/kira-96/Inno-Setup-Chinese-Simplified-Translation/977acab5e417a7b17e3fb83fee13a3cc9394f33d/LICENSE)
  is copied verbatim to `ChineseSimplified-LICENSE.txt`, copyright
  (c) 2019–2020 kirakira. SHA-256:
  `02f0dd3b98833040147d01daf91243c24392a33ddced674152220b5216782c6a`.
- The installer distributes this license as
  `{app}\licenses\InnoSetup-ChineseSimplified-LICENSE.txt`.

All 261 standard `[Messages]` keys and their numbered placeholders match
[Inno Setup 6.3.3's official Default.isl](https://github.com/jrsoftware/issrc/blob/is-6_3_3/Files/Default.isl).
The file therefore needs no 6.4+ message directives. When changing compiler
versions, compare the standard message keys again; a newer compiler may add
messages requiring an updated translation. The installer source is UTF-8, which
[Inno Setup 6.3 accepts without a BOM](https://jrsoftware.org/ishelp/topic_unicode.htm).

Keep this directory beside `installer.iss` when transferring build sources. No
language resource is fetched at build or install time. Static checks establish
key/placeholder coverage and encoding, not a successful Windows compilation or
visual layout check; those require the Windows release worker.
