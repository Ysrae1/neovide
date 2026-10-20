# Native Windows CMatrix Glow

This builds the existing Glow Unimatrix/Gomatrix animation for Windows x64.
It keeps the current intro and dashboard commands, including
`cmatrix-gm --intro --fps 60 --fade 4 -o` and
`cmatrix-gm --fps 60 --fade 4 --length 9:13 -o`.

The scheduler, glyph sets, white heads, brightness/fade levels, stream lengths,
per-stream timers, asynchronous updates and offscreen intro are copied from
`portable/payload/patches/cmatrix-unimatrix.patch`. `unimatrix.c` has only seven
adapter changes: curses/getopt/process includes, the monotonic clock, bounded
sleep, Windows UTF-8 locale and a terminal disconnect/control-event stop hook.
The original Unix patch and upstream CMatrix source remain unchanged.

`vt_terminal.c` supplies the small curses surface that this scheduler uses.
It buffers updates until `refresh()`, emits RGB VT sequences and UTF-8, reads
Windows console keyboard/resize events, and restores terminal modes, cursor
and alternate screen when the animation exits. Its 31-bit random adapter
avoids MSVC's 15-bit `RAND_MAX` limit for large timer ranges; randomized frame
contents are not expected to be identical between platforms. It uses only
Windows system APIs and the statically linked MSVC runtime, with no ncurses,
PDCurses, WSL or extra runtime DLLs.

Build on a Windows release runner with Visual Studio 2022 C++ tools and CMake:

```powershell
& .\portable\windows\matrix\build.ps1 `
  -BuildDirectory "$env:RUNNER_TEMP\glow-matrix-build" `
  -OutputDirectory '.\stage\tools\bin'
```

Equivalent commands from the repository root:

```powershell
cmake -S portable/windows/matrix -B build/matrix -G 'Visual Studio 17 2022' -A x64
cmake --build build/matrix --config Release --parallel
```

`build/matrix/Release` contains three copies of the same native console PE:

| File | Default mode |
| --- | --- |
| `cmatrix-gm.exe` | Gomatrix; preserves the existing `cmatrix-gm` wrapper |
| `cmatrix-uni.exe` | Unimatrix |
| `cmatrix-uni-native.exe` | Unimatrix; accepts explicit `--gomatrix` |

All accept `--unimatrix`; `--gomatrix` selects the Gomatrix scheduler.
Existing `--intro`, `--fps`, `--fade`, `--length`, `-o`, `-t`, character/color
and keyboard options retain their validation. The classic original CMatrix
renderer is not exposed as `cmatrix.exe`: this port is the existing Glow rain
used by Neovide, not a replacement with different startup visuals.

For interactive use, stdout must be a Windows VT console, including Neovim's
ConPTY. Console size is read dynamically through Win32; redirected output
uses `LINES`/`COLUMNS` (default 24x80) and cannot receive console resize events.
Closed pipes stop the scheduler. `--help`/`--version` require no terminal.

Validation available on macOS is limited to source equivalence, option-parser
fixtures and mocked Win32 adapter checks. A successful Windows compilation and
actual Neovim ConPTY resize/keyboard/intro run must still be recorded before
claiming native Windows animation acceptance.

## Licenses

The animation is GPL-3.0-or-later, with the Gomatrix BSD-2-Clause notice retained
inside `unimatrix.c`. Distribute `portable/licenses/CMatrix-Unimatrix-GPL3.txt`
and `portable/licenses/Gomatrix-BSD-2-Clause.txt` with binaries, and provide the
corresponding source (`portable/windows/matrix` and the referenced payload
patch). Unimatrix attribution remains William Mannard; Gomatrix copyright is
Geert-Johan Riemer and Garrett D'Amore. This Win32 adapter is by Codex, 2026-10-20.
