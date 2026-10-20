/* SPDX-License-Identifier: GPL-3.0-or-later
 * Small Win32 VT adapter for the curses calls used by unimatrix.c.
 * This is not a general curses replacement. No terminal, runtime or DLL
 * installation is required; Windows 10+ and Neovim's ConPTY are supported. */
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0a00
#include <windows.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "vt_terminal.h"
#ifndef DISABLE_NEWLINE_AUTO_RETURN
#define DISABLE_NEWLINE_AUTO_RETURN 0x0008
#endif
#ifndef CREATE_WAITABLE_TIMER_HIGH_RESOLUTION
#define CREATE_WAITABLE_TIMER_HIGH_RESOLUTION 0x00000002
#endif

int LINES = 24, COLS = 80, COLORS = 16777216;
static WINDOW screen_window;
WINDOW *stdscr = &screen_window;
static SCREEN screen;
static HANDLE input_handle, output_handle, sleep_timer;
static DWORD input_mode, output_mode, input_codepage, output_codepage;
static int input_console, output_console, active, io_failed, clear_pending;
static unsigned short repeat_count;
static int repeat_key;
static volatile sig_atomic_t *stop_flag;
static cchar_t *cells, *presented;
static unsigned char *valid;
static struct { int fg, bg, direct; } pairs[32];
static attr_t attributes, background = COLOR_PAIR(1);
static char output_buffer[65536];
static size_t output_length;
static uint32_t random_state = 1;

void matrix_srand(unsigned int seed) { random_state = seed ? seed : 1; }
int matrix_rand(void) {
    uint32_t value = random_state;
    value ^= value << 13; value ^= value >> 17; value ^= value << 5;
    random_state = value;
    return (int)(value & UINT32_C(0x7fffffff));
}

static void request_stop(void) { if (stop_flag) *stop_flag = 1; }
void matrix_set_stop_flag(volatile sig_atomic_t *flag) { stop_flag = flag; }
static BOOL WINAPI console_control(DWORD event) {
    switch (event) {
    case CTRL_C_EVENT: case CTRL_BREAK_EVENT: case CTRL_CLOSE_EVENT:
    case CTRL_LOGOFF_EVENT: case CTRL_SHUTDOWN_EVENT: request_stop(); return TRUE;
    default: return FALSE;
    }
}
static int flush_output(void) {
    size_t offset = 0;
    if (io_failed) { output_length = 0; return ERR; }
    while (offset < output_length) {
        DWORD written = 0;
        if (!WriteFile(output_handle, output_buffer+offset, (DWORD)(output_length-offset), &written, NULL) || !written) {
            io_failed = 1; request_stop(); output_length = 0; return ERR;
        }
        offset += written;
    }
    output_length = 0;
    return OK;
}
static void append_output(const char *text, size_t length) {
    if (io_failed) return;
    while (length) {
        size_t room = sizeof(output_buffer)-output_length;
        size_t portion = length < room ? length : room;
        memcpy(output_buffer+output_length, text, portion);
        output_length += portion; text += portion; length -= portion;
        if (output_length == sizeof(output_buffer) && flush_output() == ERR) return;
    }
}
static void text_output(const char *text) { append_output(text, strlen(text)); }
static void codepoint_output(unsigned int point) {
    char bytes[4]; size_t length;
    if (point < 0x80) { bytes[0] = (char)point; length = 1; }
    else if (point < 0x800) { bytes[0]=(char)(0xc0|(point>>6)); bytes[1]=(char)(0x80|(point&63)); length=2; }
    else if (point < 0x10000) { bytes[0]=(char)(0xe0|(point>>12)); bytes[1]=(char)(0x80|((point>>6)&63)); bytes[2]=(char)(0x80|(point&63)); length=3; }
    else { bytes[0]=(char)(0xf0|(point>>18)); bytes[1]=(char)(0x80|((point>>12)&63)); bytes[2]=(char)(0x80|((point>>6)&63)); bytes[3]=(char)(0x80|(point&63)); length=4; }
    append_output(bytes, length);
}
static int environment_dimension(const char *name, int fallback) {
    const char *value = getenv(name); char *end;
    if (!value) return fallback;
    long number = strtol(value, &end, 10);
    return end != value && !*end && number > 0 && number <= 32767 ? (int)number : fallback;
}
static int update_dimensions(void) {
    CONSOLE_SCREEN_BUFFER_INFO info;
    int rows = LINES, cols = COLS;
    if (GetConsoleScreenBufferInfo(output_handle, &info)) {
        rows = info.srWindow.Bottom-info.srWindow.Top+1;
        cols = info.srWindow.Right-info.srWindow.Left+1;
    } else if (!cells) {
        rows = environment_dimension("LINES", 24); cols = environment_dimension("COLUMNS", 80);
    }
    if (cells && rows == LINES && cols == COLS) return 0;
    if (rows < 1 || cols < 1 || (size_t)rows*(size_t)cols > 16000000) { request_stop(); return ERR; }
    size_t count = (size_t)rows*(size_t)cols;
    cchar_t *next = calloc(count, sizeof(*next));
    cchar_t *last = calloc(count, sizeof(*last));
    unsigned char *seen = calloc(count, 1);
    if (!next || !last || !seen) {
        free(next); free(last); free(seen); request_stop(); return ERR;
    }
    free(cells); free(presented); free(valid);
    cells = next; presented = last; valid = seen; LINES = rows; COLS = cols;
    clear_pending = 1;
    erase();
    return 1;
}
static void restore_terminal(void) {
    if (!active) return;
    text_output("\x1b[0m\x1b[?25h\x1b[?1049l"); flush_output();
    if (input_console) SetConsoleMode(input_handle, input_mode);
    if (output_console) SetConsoleMode(output_handle, output_mode);
    if (input_codepage) SetConsoleCP(input_codepage);
    if (output_codepage) SetConsoleOutputCP(output_codepage);
    SetConsoleCtrlHandler(console_control, FALSE);
    if (sleep_timer) { CloseHandle(sleep_timer); sleep_timer = NULL; }
    free(cells); free(presented); free(valid);
    cells = presented = NULL; valid = NULL; active = 0;
}
WINDOW *initscr(void) {
    if (active) return stdscr;
    input_handle = GetStdHandle(STD_INPUT_HANDLE); output_handle = GetStdHandle(STD_OUTPUT_HANDLE);
    input_console = GetConsoleMode(input_handle, &input_mode) != 0;
    output_console = GetConsoleMode(output_handle, &output_mode) != 0;
    if (output_console && !SetConsoleMode(output_handle, output_mode|ENABLE_VIRTUAL_TERMINAL_PROCESSING|DISABLE_NEWLINE_AUTO_RETURN)) {
        fputs("CMatrix Glow requires a Windows VT terminal or Neovim ConPTY.\n", stderr); exit(2);
    }
    if (input_console) {
        DWORD mode = (input_mode|ENABLE_WINDOW_INPUT|ENABLE_EXTENDED_FLAGS) &
            ~(ENABLE_LINE_INPUT|ENABLE_ECHO_INPUT|ENABLE_PROCESSED_INPUT|ENABLE_QUICK_EDIT_MODE|ENABLE_VIRTUAL_TERMINAL_INPUT);
        if (!SetConsoleMode(input_handle, mode)) {
            if (output_console) SetConsoleMode(output_handle, output_mode);
            fputs("Cannot put the Windows terminal into input mode.\n", stderr); exit(2);
        }
    }
    input_codepage = GetConsoleCP(); output_codepage = GetConsoleOutputCP();
    if (input_codepage) SetConsoleCP(CP_UTF8);
    if (output_codepage) SetConsoleOutputCP(CP_UTF8);
    active = 1; io_failed = 0;
    atexit(restore_terminal); SetConsoleCtrlHandler(console_control, TRUE);
    if (update_dimensions() == ERR) { restore_terminal(); fputs("Cannot allocate terminal canvas.\n", stderr); exit(1); }
    text_output("\x1b[?1049h\x1b[?25l\x1b[0m\x1b[2J\x1b[H"); flush_output();
    return stdscr;
}
SCREEN *newterm(const char *name, FILE *output, FILE *input) {
    (void)name; (void)output; (void)input; initscr(); return &screen;
}
void delscreen(SCREEN *value) { (void)value; }
int endwin(void) { restore_terminal(); return OK; }
WINDOW *newwin(int rows, int cols, int y, int x) {
    (void)rows; (void)cols; (void)y; (void)x;
    WINDOW *window = calloc(1, sizeof(*window));
    if (window) window->input_only = 1;
    return window;
}
int delwin(WINDOW *window) { free(window); return OK; }
int cbreak(void) { return OK; }
int noecho(void) { return OK; }
int keypad(WINDOW *window, int value) { (void)window; (void)value; return OK; }
int nodelay(WINDOW *window, int value) { (void)window; (void)value; return OK; }
int untouchwin(WINDOW *window) { (void)window; return OK; }
int curs_set(int visibility) {
    text_output(visibility ? "\x1b[?25h" : "\x1b[?25l"); return flush_output();
}
int start_color(void) { return OK; }
int use_default_colors(void) { return OK; }
int init_extended_pair(int pair, int fg, int bg) {
    if (pair < 0 || pair >= 32) return ERR;
    pairs[pair].fg = fg; pairs[pair].bg = bg; pairs[pair].direct = 1;
    if (valid) memset(valid, 0, (size_t)LINES*(size_t)COLS);
    return OK;
}
int init_pair(short pair, short fg, short bg) {
    if (init_extended_pair(pair, fg, bg) == ERR) return ERR;
    pairs[pair].direct = 0; return OK;
}
int bkgd(attr_t value) { background = value; return OK; }
int erase(void) {
    if (!cells) return ERR;
    cchar_t blank = {{L' ', 0, 0}, background & 0xffu, (short)(background>>8)};
    for (size_t i = 0; i < (size_t)LINES*(size_t)COLS; ++i) cells[i] = blank;
    return OK;
}
static int console_key(void) {
    INPUT_RECORD record; DWORD available, read;
    if (repeat_count) { --repeat_count; return repeat_key; }
    while (PeekConsoleInputW(input_handle, &record, 1, &available) && available) {
        if (!ReadConsoleInputW(input_handle, &record, 1, &read) || !read) break;
        if (record.EventType == WINDOW_BUFFER_SIZE_EVENT) {
            if (update_dimensions() > 0) return KEY_RESIZE;
            continue;
        }
        if (record.EventType != KEY_EVENT || !record.Event.KeyEvent.bKeyDown) continue;
        KEY_EVENT_RECORD *event = &record.Event.KeyEvent;
        int value = event->uChar.UnicodeChar;
        if (value == 3) { request_stop(); return ERR; }
        switch (event->wVirtualKeyCode) {
        case VK_LEFT: value = KEY_LEFT; break; case VK_RIGHT: value = KEY_RIGHT; break;
        case VK_UP: value = KEY_UP; break; case VK_DOWN: value = KEY_DOWN; break;
        default: break;
        }
        if (!value) continue;
        repeat_key = value; repeat_count = event->wRepeatCount ? (unsigned short)(event->wRepeatCount-1) : 0;
        return value;
    }
    return ERR;
}
static int pipe_key(void) {
    unsigned char byte; DWORD available = 0, read = 0;
    if (!PeekNamedPipe(input_handle, NULL, 0, NULL, &available, NULL)) {
        DWORD error = GetLastError();
        if (error == ERROR_BROKEN_PIPE || error == ERROR_PIPE_NOT_CONNECTED) request_stop();
        /* A redirected regular file is safe to read only when signalled. */
        if (error != ERROR_INVALID_FUNCTION || WaitForSingleObject(input_handle, 0) != WAIT_OBJECT_0) return ERR;
        available = 1;
    }
    if (!available) return ERR;
    if (!ReadFile(input_handle, &byte, 1, &read, NULL) || !read) { request_stop(); return ERR; }
    if (byte == 3) { request_stop(); return ERR; }
    if (byte == 27 && available >= 3) {
        unsigned char tail[2];
        if (ReadFile(input_handle, tail, 2, &read, NULL) && read == 2 && tail[0] == '[') {
            switch (tail[1]) {
            case 'A': return KEY_UP; case 'B': return KEY_DOWN;
            case 'C': return KEY_RIGHT; case 'D': return KEY_LEFT;
            default: break;
            }
        }
    }
    return byte;
}
int wgetch(WINDOW *window) {
    (void)window;
    int resized = update_dimensions();
    if (resized == ERR) { request_stop(); return ERR; }
    if (resized) return KEY_RESIZE;
    return input_console ? console_key() : pipe_key();
}
int getch(void) { return wgetch(stdscr); }
int setcchar(cchar_t *cell, const wchar_t *text, attr_t value, short pair, const void *unused) {
    (void)unused;
    if (!cell || !text || !text[0] || pair < 0 || pair >= 32) return ERR;
    cell->text[0] = text[0]; cell->text[1] = text[1]; cell->text[2] = 0;
    cell->attributes = value; cell->pair = pair; return OK;
}
int mvadd_wch(int y, int x, const cchar_t *cell) {
    if (y < 0 || x < 0 || y >= LINES || x >= COLS || !cells) return ERR;
    cells[(size_t)y*(size_t)COLS+(size_t)x] = *cell; return OK;
}
int attron(attr_t value) { attributes |= value; return OK; }
int attroff(attr_t value) { attributes &= ~value; return OK; }
int mvaddnstr(int y, int x, const char *text, int length) {
    if (length < 0) length = (int)strlen(text);
    for (int i = 0; i < length && text[i]; ++i) {
        cchar_t cell = {{(unsigned char)text[i], 0, 0}, attributes & 0xffu, (short)(attributes>>8)};
        if (mvadd_wch(y, x+i, &cell) == ERR) return ERR;
    }
    return OK;
}
int mvaddstr(int y, int x, const char *text) { return mvaddnstr(y, x, text, -1); }
static void color_output(int value, int direct, int foreground) {
    char sequence[64];
    if (value < 0) snprintf(sequence, sizeof(sequence), "\x1b[%dm", foreground ? 39 : 49);
    else if (direct && foreground) snprintf(sequence, sizeof(sequence), "\x1b[38;2;%d;%d;%dm", (value>>16)&255, (value>>8)&255, value&255);
    else if (value < 8) snprintf(sequence, sizeof(sequence), "\x1b[%dm", (foreground ? 30 : 40)+value);
    else snprintf(sequence, sizeof(sequence), "\x1b[%d;5;%dm", foreground ? 38 : 48, value);
    text_output(sequence);
}
int refresh(void) {
    int last_pair = -1; attr_t last_attributes = (attr_t)-1;
    if (io_failed || !cells) return ERR;
    if (clear_pending) { text_output("\x1b[0m\x1b[2J\x1b[H"); clear_pending = 0; }
    for (int y = 0; y < LINES; ++y) for (int x = 0; x < COLS; ++x) {
        size_t position = (size_t)y*(size_t)COLS+(size_t)x;
        const cchar_t *cell = &cells[position];
        const cchar_t *old = &presented[position];
        if (valid[position] && cell->text[0] == old->text[0] && cell->text[1] == old->text[1] &&
            cell->attributes == old->attributes && cell->pair == old->pair) continue;
        char move[48]; snprintf(move, sizeof(move), "\x1b[%d;%dH", y+1, x+1); text_output(move);
        if (cell->attributes != last_attributes || cell->pair != last_pair) {
            text_output(cell->attributes&A_BOLD ? "\x1b[0;1m" : "\x1b[0m");
            color_output(pairs[cell->pair].fg, pairs[cell->pair].direct, 1);
            color_output(pairs[cell->pair].bg, 0, 0);
            last_pair = cell->pair; last_attributes = cell->attributes;
        }
        codepoint_output((unsigned int)cell->text[0]);
        if (cell->text[1]) codepoint_output((unsigned int)cell->text[1]);
        presented[position] = *cell; valid[position] = 1;
    }
    return flush_output();
}
double matrix_monotonic(void) {
    LARGE_INTEGER now, frequency;
    QueryPerformanceFrequency(&frequency); QueryPerformanceCounter(&now);
    return (double)now.QuadPart/(double)frequency.QuadPart;
}
void matrix_sleep_seconds(double seconds) {
    if (seconds <= 0) return;
    if (!sleep_timer) {
        sleep_timer = CreateWaitableTimerExW(NULL, NULL, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
        if (!sleep_timer) sleep_timer = CreateWaitableTimerW(NULL, FALSE, NULL);
    }
    LARGE_INTEGER due; due.QuadPart = -(LONGLONG)(seconds*10000000.0);
    if (!due.QuadPart) due.QuadPart = -1;
    if (sleep_timer && SetWaitableTimer(sleep_timer, &due, 0, NULL, NULL, FALSE)) WaitForSingleObject(sleep_timer, INFINITE);
    else Sleep((DWORD)(seconds*1000.0)+1);
}
int napms(int milliseconds) { matrix_sleep_seconds(milliseconds/1000.0); return OK; }
int matrix_wcwidth(wchar_t character) {
    unsigned int c = (unsigned int)character; WORD classification = 0;
    if (!c) return 0;
    if (c < 32 || (c >= 0x7f && c < 0xa0) || (c >= 0xd800 && c <= 0xdfff)) return -1;
    /* Half-width kana and its two voicing marks are explicitly single-cell. */
    if (c >= 0xff61 && c <= 0xff9f) return 1;
    if (GetStringTypeW(CT_CTYPE3, &character, 1, &classification) && (classification&C3_NONSPACING)) return 0;
    if (c >= 0x1100 && (c <= 0x115f || c == 0x2329 || c == 0x232a ||
        (c >= 0x2e80 && c <= 0xa4cf && c != 0x303f) || (c >= 0xac00 && c <= 0xd7a3) ||
        (c >= 0xf900 && c <= 0xfaff) || (c >= 0xfe10 && c <= 0xfe19) ||
        (c >= 0xfe30 && c <= 0xfe6f) || (c >= 0xff00 && c <= 0xff60) ||
        (c >= 0xffe0 && c <= 0xffe6))) return 2;
    return 1;
}
