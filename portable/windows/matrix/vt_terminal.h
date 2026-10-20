/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef MATRIX_VT_TERMINAL_H
#define MATRIX_VT_TERMINAL_H
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

/* The bounded curses surface used by unimatrix.c. All drawing is buffered
 * until refresh(), preserving the scheduler's offscreen intro and FPS limit. */
typedef unsigned int attr_t;
typedef struct { int input_only; } WINDOW;
typedef struct { int unused; } SCREEN;
typedef struct { wchar_t text[3]; attr_t attributes; short pair; } cchar_t;
extern int LINES, COLS, COLORS;
extern WINDOW *stdscr;
#define TRUE 1
#define OK 0
#define ERR (-1)
#define A_NORMAL 0u
#define A_BOLD 1u
#define COLOR_PAIR(pair) ((attr_t)(pair) << 8)
#define COLOR_BLACK 0
#define COLOR_RED 1
#define COLOR_GREEN 2
#define COLOR_YELLOW 3
#define COLOR_BLUE 4
#define COLOR_MAGENTA 5
#define COLOR_CYAN 6
#define COLOR_WHITE 7
#define KEY_RESIZE 0x100
#define KEY_LEFT 0x101
#define KEY_RIGHT 0x102
#define KEY_UP 0x103
#define KEY_DOWN 0x104

WINDOW *initscr(void);
SCREEN *newterm(const char *name, FILE *output, FILE *input);
void delscreen(SCREEN *screen);
int endwin(void);
WINDOW *newwin(int rows, int cols, int y, int x);
int delwin(WINDOW *window);
int cbreak(void);
int noecho(void);
int keypad(WINDOW *window, int value);
int nodelay(WINDOW *window, int value);
int untouchwin(WINDOW *window);
int curs_set(int visibility);
int start_color(void);
int use_default_colors(void);
int init_pair(short pair, short fg, short bg);
int init_extended_pair(int pair, int fg, int bg);
int bkgd(attr_t attributes);
int erase(void);
int getch(void);
int wgetch(WINDOW *window);
int setcchar(cchar_t *cell, const wchar_t *text, attr_t attributes, short pair, const void *unused);
int mvadd_wch(int y, int x, const cchar_t *cell);
int attron(attr_t attributes);
int attroff(attr_t attributes);
int mvaddnstr(int y, int x, const char *text, int length);
int mvaddstr(int y, int x, const char *text);
int refresh(void);
int napms(int milliseconds);
int matrix_wcwidth(wchar_t character);
#define wcwidth matrix_wcwidth
double matrix_monotonic(void);
void matrix_sleep_seconds(double seconds);
void matrix_set_stop_flag(volatile sig_atomic_t *flag);
/* MSVC's RAND_MAX is only 32767. Larger terminal/async timer ranges must
 * retain the scheduler's unbiased inclusive sampling rather than loop forever. */
int matrix_rand(void);
void matrix_srand(unsigned int seed);
#undef RAND_MAX
#define RAND_MAX 2147483647
#define rand matrix_rand
#define srand matrix_srand
#endif
