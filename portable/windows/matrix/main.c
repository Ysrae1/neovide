/* SPDX-License-Identifier: GPL-3.0-or-later */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include "unimatrix.h"

/* Wide argv avoids dependence on the user's ANSI code page for -u UTF8. */
int wmain(int argc, wchar_t **wide_argv) {
    char **argv = calloc((size_t)argc+2, sizeof(*argv));
    char **allocated = calloc((size_t)argc, sizeof(*allocated));
    int count = 0, result = 1;
    if (!argv || !allocated) goto finish;
    for (int i = 0; i < argc; ++i) {
        int length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide_argv[i], -1, NULL, 0, NULL, NULL);
        if (!length || !(allocated[i] = malloc((size_t)length))) goto finish;
        if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide_argv[i], -1, allocated[i], length, NULL, NULL)) goto finish;
    }
    argv[count++] = allocated[0];
    const wchar_t *name = wcsrchr(wide_argv[0], L'\\');
    const wchar_t *slash = wcsrchr(wide_argv[0], L'/');
    if (!name || (slash && slash > name)) name = slash;
    name = name ? name+1 : wide_argv[0];
    if (!_wcsicmp(name, L"cmatrix-gm.exe") || !_wcsicmp(name, L"cmatrix-gm")) argv[count++] = "--gomatrix";
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(allocated[i], "--unimatrix")) continue;
        if (!strcmp(allocated[i], "--version")) {
            puts("cmatrix-gm 2.0-gm (native Windows VT; Glow Unimatrix/Gomatrix scheduler)");
            result = 0; goto finish;
        }
        argv[count++] = allocated[i];
    }
    result = unimatrix_main(count, argv);
finish:
    if (allocated) for (int i = 0; i < argc; ++i) free(allocated[i]);
    free(allocated); free(argv);
    return result;
}
