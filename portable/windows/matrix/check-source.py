#!/usr/bin/env python3
"""Assert this port retains the frozen rain implementation plus bounded adapters."""
from pathlib import Path

matrix = Path(__file__).resolve().parent
patch = (matrix.parents[1] / "payload/patches/cmatrix-unimatrix.patch").read_text()
start = patch.index("diff --git a/unimatrix.c b/unimatrix.c\n")
end = patch.index("diff --git ", start + 12)
source = "".join(
    line[1:] + "\n" for line in patch[start:end].splitlines()
    if line.startswith("+") and not line.startswith("+++")
)
adapters = {
    "#include <ncurses.h>": '#include "vt_terminal.h"',
    "#include <unistd.h>": "#include <process.h>\n#define getpid _getpid",
    "#include <getopt.h>": '#include "getopt_compat.h"',
    "static double rain_time(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }":
        "static double rain_time(void) { return matrix_monotonic(); }",
    "if(remaining>0){struct timespec wait={0,(long)(remaining*1e9)};nanosleep(&wait,NULL);}":
        "if(remaining>0)matrix_sleep_seconds(remaining);",
    'setlocale(LC_ALL,"")': 'setlocale(LC_ALL,".UTF8")',
    "    rain_stop=0;": "    rain_stop=0;matrix_set_stop_flag(&rain_stop);",
}
for original, adapted in adapters.items():
    assert source.count(original) == 1, f"Unexpected upstream adapter anchor: {original}"
    source = source.replace(original, adapted)
actual = (matrix / "unimatrix.c").read_text()
preamble_end = actual.index("*/\n") + 3
assert actual[preamble_end:] == source, "Windows rain logic diverged from the payload patch"
print("PASS: exact rain implementation with seven bounded Windows adapters")
