/* SPDX-License-Identifier: GPL-3.0-or-later */
#include <stddef.h>
#include <string.h>
#include "getopt_compat.h"
char *optarg;
int optind = 1, opterr = 1;
static size_t short_position;

int getopt_long(int argc, char *const argv[], const char *short_options,
                const struct option *long_options, int *long_index) {
    const char *argument, *definition;
    int value;
    optarg = NULL;
    if (optind >= argc) return -1;
    argument = argv[optind];
    if (!short_position) {
        if (argument[0] != '-' || !argument[1]) return -1;
        if (!strcmp(argument, "--")) { ++optind; return -1; }
        if (argument[1] == '-') {
            const char *name = argument + 2, *equal = strchr(name, '=');
            size_t length = equal ? (size_t)(equal-name) : strlen(name);
            int selected = -1, matches = 0;
            ++optind;
            for (int i = 0; long_options[i].name; ++i) {
                if (!strncmp(name, long_options[i].name, length)) {
                    selected = i; ++matches;
                    if (strlen(long_options[i].name) == length) { matches = 1; break; }
                }
            }
            if (matches != 1) return '?';
            const struct option *option = &long_options[selected];
            if (long_index) *long_index = selected;
            if (option->has_arg == required_argument) {
                if (equal) optarg = (char *)equal + 1;
                else if (optind < argc) optarg = argv[optind++];
                else return '?';
            } else if (equal) return '?';
            if (option->flag) { *option->flag = option->val; return 0; }
            return option->val;
        }
        short_position = 1;
    }
    value = (unsigned char)argument[short_position++];
    definition = strchr(short_options, value);
    if (!definition || value == ':') {
        if (!argument[short_position]) { short_position = 0; ++optind; }
        return '?';
    }
    if (definition[1] == ':') {
        if (argument[short_position]) optarg = (char *)argument + short_position;
        else if (optind+1 < argc) optarg = argv[++optind];
        else { short_position = 0; ++optind; return '?'; }
        short_position = 0; ++optind;
    } else if (!argument[short_position]) { short_position = 0; ++optind; }
    return value;
}
