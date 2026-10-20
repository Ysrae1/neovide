/* SPDX-License-Identifier: GPL-3.0-or-later */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "getopt_compat.h"
int main(void) {
    const struct option options[] = {
        {"gomatrix", no_argument, NULL, 1000}, {"fps", required_argument, NULL, 1001},
        {"fade", required_argument, NULL, 1002}, {"intro", no_argument, NULL, 1003},
        {"length", required_argument, NULL, 1004}, {"help", no_argument, NULL, 'h'}, {NULL, 0, NULL, 0}
    };
    char *argv[] = {"cmatrix", "--gomatrix", "--intro", "--fps=60", "--fade", "4", "--length", "9:13", "-oi", "-s98", "-u", "abc", "--", "tail"};
    int argc = (int)(sizeof(argv)/sizeof(*argv));
    assert(getopt_long(argc, argv, "ois:u:h", options, NULL) == 1000);
    assert(getopt_long(argc, argv, "ois:u:h", options, NULL) == 1003);
    assert(getopt_long(argc, argv, "ois:u:h", options, NULL) == 1001 && !strcmp(optarg, "60"));
    assert(getopt_long(argc, argv, "ois:u:h", options, NULL) == 1002 && !strcmp(optarg, "4"));
    assert(getopt_long(argc, argv, "ois:u:h", options, NULL) == 1004 && !strcmp(optarg, "9:13"));
    assert(getopt_long(argc, argv, "ois:u:h", options, NULL) == 'o');
    assert(getopt_long(argc, argv, "ois:u:h", options, NULL) == 'i');
    assert(getopt_long(argc, argv, "ois:u:h", options, NULL) == 's' && !strcmp(optarg, "98"));
    assert(getopt_long(argc, argv, "ois:u:h", options, NULL) == 'u' && !strcmp(optarg, "abc"));
    assert(getopt_long(argc, argv, "ois:u:h", options, NULL) == -1 && !strcmp(argv[optind], "tail"));
    optind = 1;
    char *bad[] = {"cmatrix", "--fps"};
    assert(getopt_long(2, bad, "h", options, NULL) == '?');
    optind = 1;
    char *ambiguous[] = {"cmatrix", "--f=60"};
    assert(getopt_long(2, ambiguous, "h", options, NULL) == '?');
    optind = 1;
    char *extra[] = {"cmatrix", "--intro=yes"};
    assert(getopt_long(2, extra, "h", options, NULL) == '?');
    puts("PASS: intro/dashboard flags, clusters, arguments and invalid options");
    return 0;
}
