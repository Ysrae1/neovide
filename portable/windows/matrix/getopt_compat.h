/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef MATRIX_GETOPT_COMPAT_H
#define MATRIX_GETOPT_COMPAT_H
#define no_argument 0
#define required_argument 1
struct option { const char *name; int has_arg; int *flag; int val; };
extern char *optarg;
extern int optind, opterr;
int getopt_long(int argc, char *const argv[], const char *short_options,
                const struct option *long_options, int *long_index);
#endif
