# Diagnostic display localization

`config.locale.diagnostics.setup()` is the internal initialization entry, called by the stable `config.platform.locale` facade.
Call it once during the existing locale setup (after locale initialization is safe),
and call `refresh()` after a live installation. It listens to the existing
`User GlowLanguageChanged` and `User LazyLoad` events. It does not write preferences,
restart servers, change interpreters, install packages, or suppress diagnostics.

## Coverage and evidence

The current configuration declares Pyright + Ruff, LuaLS, clangd, gopls, jsonls,
Marksman, Texlab, LTeX, and neocmake. The explicit none-ls source override contains
mypy, yamllint, and ShellCheck diagnostics. These are *configured sources*; their
actual startup still depends on file type, executable availability and workspace.
For example, ShellCheck has a source specification but no executable was found in
the inspected Mac PATH; this change does not install it. Other optional tools listed
in Mason are not automatically treated as enabled diagnostic providers.

| Source family | Inspected package/version | Covered common cases |
| --- | --- | --- |
| mypy | 1.15.0 | missing module vs missing type stubs, assignment/call/return types, missing annotation, unused ignore |
| Pyright | 1.1.414 | imports, unbound/undefined/unused names, assignment/argument/return types, syntax, unreachable code |
| Ruff | 0.9.6 | F401/F821/F841/F823, import placement/sorting, whitespace, line length, bare except |
| LuaLS | 3.13.6 | globals/fields/types, unused/redefined values, arguments, annotations, nil, deprecated APIs |
| clangd | 19.1.2 | unknown names/types/members, missing include, syntax, unused values, call/return mismatch |
| gopls | v0.22.0 | undefined/unused symbols, imports, return count, assignment, unused parameters |
| jsonls | vscode-langservers-extracted 4.10.0 | JSON grammar, schema-required/forbidden properties and types |
| Marksman | 2024-12-18 | missing/ambiguous link destinations, nonbreaking heading whitespace |
| Texlab | v5.22.1 | reference/label/BibTeX checks, environment/braces, common TeX build messages |
| neocmake | v0.10.2 | syntax, dependency/include/path problems, selected cmakelint messages |
| yamllint | 1.35.1 | indentation, duplicates, booleans, spacing, document marker |
| ShellCheck | configured optional executable | SC2086/2034/2154/2006/1090/2148 |
| LTeX | 16.0.0 | common spelling, sentence capitalization and repeated-space messages |

191 curated, source-scoped English/Chinese templates are in
`lua/config/platform/diagnostic_messages.lua`. Rule codes are checked when supplied.
Known upstream Pyright/LuaLS Chinese variants are accepted too, so a server that
started under Chinese can still render supported messages in English. Ambiguous
upstream wording is deliberately not reverse-guessed. Placeholders preserve names,
paths, package names, types, numbers, commands and URLs byte-for-byte. Unknown
messages and unmatched detail lines stay exactly as the tool produced them.

This is not a claim that every diagnostic from every language server is translated.
In particular, arbitrary clang-tidy/staticcheck rules, LanguageTool grammar rules,
custom schema error text and full TeX/chktex logs remain open-ended upstream data.
Their unrecognized text remains visible; it is never replaced by a vague generic
error. Add an exact source/code/template and corresponding fixture when a new
message is reported. No user code or diagnostic is sent to a translation service.

Official evidence used before implementation:

- [Pyright locale configuration](https://github.com/microsoft/pyright/blob/main/docs/configuration.md#locale-configuration) and the versioned [English](https://github.com/microsoft/pyright/blob/1.1.414/packages/pyright-internal/src/localization/package.nls.en-us.json) / [Chinese](https://github.com/microsoft/pyright/blob/1.1.414/packages/pyright-internal/src/localization/package.nls.zh-cn.json) messages.
- [LuaLS locale command option](https://luals.github.io/wiki/usage/) and installed 3.13.6 locale strings ([official source](https://github.com/LuaLS/lua-language-server/blob/3.13.6/locale/zh-cn/script.lua)).
- [mypy error codes](https://mypy.readthedocs.io/en/stable/error_code_list.html), [Ruff rules](https://docs.astral.sh/ruff/rules/), and their installed none-ls parsing configuration.
- [Texlab diagnostic messages](https://github.com/latex-lsp/texlab/blob/v5.22.1/crates/diagnostics/src/types.rs), [Marksman diagnostics](https://github.com/artempyanykh/marksman/blob/2024-12-18/Marksman/Diag.fs), [neocmake grammar diagnostics](https://github.com/neocmakelsp/neocmakelsp/blob/v0.10.2/src/grammar.rs).
- Installed vscode-json-languageservice parser/schema templates, yamllint/none-ls source, and [ShellCheck rules](https://www.shellcheck.net/wiki/SC2086).
- [LTeX settings](https://valentjn.github.io/ltex/settings.html): `ltex.language` changes the language **being checked**, not a general UI translation preference. It is not changed here.
- [Neovim diagnostic display API](https://neovim.io/doc/user/diagnostic/): the built-in format option supports presentation without altering cached diagnostics.

Pyright and LuaLS provide process-level localization controls. They do not by
themselves refresh all already-rendered menus/lists when Glow changes language.
The shared display catalog therefore remains necessary. No broad locale switch is
sent to unrelated tools. English/Chinese templates are reviewed by meaning: e.g.
missing implementation is distinct from missing type stubs, and an unused import
is not described as a failed import.

## Display boundaries

- Native `virtual_text` and `virtual_lines`: compose their format callbacks on a
  shallow options copy. Existing disabled state, severity/signs/underline options,
  custom formatter filtering, diagnostic source/code and original cache remain.
- Native diagnostic float: compose format and retain owned float records. Refresh
  those buffers in place, including known related-information text. Byte highlight
  ranges move with translated text; source window, locations and `gf` targets remain.
  It does not scan or rewrite arbitrary floating buffers. Floats opened before
  initial setup acquire this behavior on their next normal opening.
- Snacks: wrap only its diagnostic formatter, retain original diagnostic item,
  source/code/file positions and search data. Existing default diagnostic pickers
  adopt the renderer. Its diagnostic-to-quickfix/location-list actions also register
  display formatting; unrelated picker actions are passed through.
- Trouble: its diagnostic message formatter reads original data. On language change,
  only rendered-segment caches for diagnostic items in open diagnostic views are
  invalidated, retaining other source data and view settings.
- Native diagnostic quickfix/location lists: list-local `quickfixtextfunc` renders
  translated copies; the actual list items remain original. Registration stores list
  ID and owning window, including when opening the location list changes focus.
  If a list item is edited or replaced later, it is no longer matched/retranslated.
- Statusline, signs and NeoTree diagnostic counters contain counts/severity icons,
  not the message text; they continue to read the original diagnostic store.

## Verification

Run separately against local then portable:

```
GLOW_TEST_CONFIG=/Users/ysrae1/.config/nvim nvim --headless --noplugin -u NONE -i NONE -l tests/lsp/diagnostic_locale.lua
GLOW_TEST_CONFIG="$PWD/portable/payload/nvim" nvim --headless --noplugin -u NONE -i NONE -l tests/lsp/diagnostic_locale.lua
```

The fixture loads actual pinned Snacks/Trouble and native Neovim handlers. It covers
all catalog templates plus independent screenshot cases, source/code mismatch and
unknown fallback; four language changes on an existing diagnostic float/Trouble
view; virtual text/lines; related information; original list rows vs rendered lists;
Snacks quickfix export; float severity ranges; and unchanged diagnostic cache and
`vim.lsp.diagnostic.from()` code-action payload. It starts no LSP process or kernel,
uses no user file contents, and writes no user preferences. The isolated runtime
can report a missing optional `markdown_inline` parser when Trouble renders; this
is not an installation request and does not affect the diagnostic assertions.
