/* Windows port: terminal, UTF-8 locale and clock adapters only.
 * Rain scheduling, stream lengths, glyph selection, colors and fades are
 * copied unchanged from portable/payload/patches/cmatrix-unimatrix.patch.
 * See README.md for provenance, the bounded adapter diff and licenses. */
/* SPDX-License-Identifier: GPL-3.0-or-later
 * Native C adaptation of will8211/unimatrix.py, commit
 * dff519f972103f91384f360f270614184de8aa92 (William Mannard).
 * Preserves its column timers / writer-eraser nodes, mixed half-width charset,
 * white-head replacement, asynchronous rhythm and documented frame delay.
 * CMatrix's original renderer and options are intentionally a separate mode.
 */
#ifndef _XOPEN_SOURCE_EXTENDED
#define _XOPEN_SOURCE_EXTENDED 1
#endif
#include "vt_terminal.h"
#include <wchar.h>
#include <locale.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <signal.h>
#include <time.h>
#include <process.h>
#define getpid _getpid
#include <limits.h>
#include "getopt_compat.h"
#include "unimatrix.h"

typedef struct { int x, timer, drawing, speed; } RainColumn;
typedef struct { int x, y, writer, white, speed, expired; wchar_t last; } RainNode;
typedef struct {
    int rows, cols, column_count;
    RainColumn *columns;
    RainNode *nodes;
    size_t count, capacity;
    unsigned char *flashers;
} RainCanvas;
typedef struct {
    int delay, asynchronous, bold, flashers, status_off, ignore_keyboard;
    int single_wave, fg, bg, status_count;
    int gomatrix, fps, fade, intro, length_min, length_max;
    double runtime;
    wchar_t chars[8192];
    size_t char_count;
    char status[80];
} RainOptions;
static volatile sig_atomic_t rain_stop;
static const wchar_t rain_katakana[] = L"ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ";
static const wchar_t rain_symbols[] = L"-=*_+|:<>\"";
static const wchar_t rain_all_symbols[] = L"`-=~!@#$%^&*()_+[]{}|\\;':\",./<>?\"";
/* Gomatrix cfb8e3310c1f: the complete 63 half-width kana / punctuation runes. */
static const wchar_t go_kana[] = L"｡｢｣､･ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝﾞﾟ";
static const wchar_t go_alphanumerics[] = L"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
/* Uniform inclusive bounds, matching Python randint rather than modulo bias. */
static int rain_rand(int low, int high) {
    unsigned long span=(unsigned long)(high-low)+1UL;
    unsigned long total=(unsigned long)RAND_MAX+1UL;
    unsigned long limit=total-total%span, value;
    do { value=(unsigned long)rand(); } while(value>=limit);
    return low+(int)(value%span);
}
static void rain_signal(int signal_number) { (void)signal_number; rain_stop = 1; }
static double rain_time(void) { return matrix_monotonic(); }
static int rain_color(const char *name) {
    static const char *names[] = {"green","red","blue","white","yellow","cyan","magenta","black","default"};
    static const int values[] = {COLOR_GREEN,COLOR_RED,COLOR_BLUE,COLOR_WHITE,COLOR_YELLOW,COLOR_CYAN,COLOR_MAGENTA,COLOR_BLACK,-1};
    for (int i = 0; i < 9; ++i) if (!strcmp(name,names[i])) return values[i];
    return INT_MIN;
}
static int rain_append(RainOptions *o, const wchar_t *chars) {
    for (; *chars; ++chars) {
        if (wcwidth(*chars) != 1 || o->char_count >= sizeof(o->chars)/sizeof(*o->chars)-1) return 0;
        o->chars[o->char_count++] = *chars;
    }
    return 1;
}
static int rain_charset(RainOptions *o, const char *letters, const wchar_t *custom) {
    o->char_count = 0;
    for (; *letters; ++letters) {
        const wchar_t *chars;
        switch (*letters) {
        case 'g':
            if (!rain_append(o,go_kana) || !rain_append(o,go_alphanumerics)) return 0;
            continue;
        case 'k': chars = rain_katakana; break;
        case 'm':
            if (!rain_append(o, rain_katakana) || !rain_append(o,L"12345678901234567890")) return 0;
            for (int n=0;n<4;++n) if (!rain_append(o,rain_symbols)) return 0;
            continue;
        case 'n': chars=L"1234567890"; break;
        case 'a': chars=L"qwertyuiopasdfghjklzxcvbnm"; break;
        case 'A': chars=L"QWERTYUIOPASDFGHJKLZXCVBNM"; break;
        case 's': chars=rain_symbols; break;
        case 'S': chars=rain_all_symbols; break;
        case 'o': chars=L"qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890`-=~!@#$%^&*()_+[]{}|\\;':\",./<>?\""; break;
        case 'u': chars=custom; break;
        default: return 0;
        }
        if (!rain_append(o,chars)) return 0;
    }
    return o->char_count > 0;
}
static void rain_free(RainCanvas *c) { free(c->columns); free(c->nodes); free(c->flashers); memset(c,0,sizeof(*c)); }
static int rain_canvas(RainCanvas *c, int rows, int cols, const RainOptions *o) {
    rain_free(c);
    if (rows < 1 || cols < 1 || (size_t)rows * (size_t)cols > 16000000) return 0;
    c->rows=rows; c->cols=cols; c->column_count=(cols+1)/2;
    c->columns=calloc((size_t)c->column_count,sizeof(*c->columns));
    c->flashers=calloc((size_t)rows*(size_t)cols,1);
    if (!c->columns || !c->flashers) return 0;
    for (int i=0;i<c->column_count;++i) {
        int timer=rain_rand(1,rows);
        int speed=rain_rand(1,3);
        c->columns[i]=(RainColumn){.x=i*2,.timer=timer,.drawing=-1,.speed=speed};
        if (o->single_wave) c->columns[i].timer=(int)(0.6*c->columns[i].timer);
    }
    erase(); return 1;
}
static int rain_spawn(RainCanvas *c, RainColumn *column, const RainOptions *o) {
    if (o->single_wave && column->drawing==0) return 1;
    column->drawing=column->drawing==1 ? 0 : 1;
    int mult=o->asynchronous ? column->speed : 1;
    if (column->drawing) {
        int max=(c->rows-3)*mult;
        if (max<3*mult) max=3*mult;
        column->timer=rain_rand(3*mult,max);
        if (o->single_wave) column->timer=(int)(0.8*column->timer);
    } else column->timer=rain_rand(mult,c->rows*mult);
    if (c->count==c->capacity) {
        size_t capacity=c->capacity ? c->capacity*2 : 128;
        RainNode *nodes=realloc(c->nodes,capacity*sizeof(*nodes));
        if (!nodes) return 0;
        c->nodes=nodes; c->capacity=capacity;
    }
    c->nodes[c->count++]=(RainNode){.x=column->x,.writer=column->drawing,.speed=column->speed,.white=column->drawing && rain_rand(0,2)==0};
    return 1;
}
static wchar_t rain_char(const RainOptions *o) { return o->chars[rain_rand(0,(int)o->char_count-1)]; }
static attr_t rain_attr(const RainOptions *o, const RainNode *n, int above) {
    if (o->bold<0) return A_NORMAL;
    if (o->bold>0 || (n->white && !above)) return A_BOLD;
    return rain_rand(0,1)==0 ? A_BOLD : A_NORMAL;
}
static void rain_put(int y,int x,wchar_t character,short pair,attr_t attr) {
    if (y<0 || x<0 || y>=LINES || x>=COLS) return;
    cchar_t cell; wchar_t text[3]={character,0,0};
    /* Half-width voicing marks are spacing characters to libc/ncurses but
     * combining characters to modern terminals. Give their Unicode-equivalent
     * combining forms a one-cell carrier, so redraws cannot append marks to
     * the preceding glyph or drift into neighbouring columns. */
    if(character==0xff9e || character==0xff9f) {
        text[0]=L' ';text[1]=character==0xff9e?0x3099:0x309a;
    }
    if (setcchar(&cell,text,attr,pair,NULL)==OK) mvadd_wch(y,x,&cell);
}
static void rain_draw(RainNode *n,const RainOptions *o) {
    attr_t attr=rain_attr(o,n,0); /* Python selects the attribute before its glyph. */
    wchar_t ch=L' ';
    if (n->writer) ch=(!n->white && n->last) ? n->last : rain_char(o);
    rain_put(n->y,n->x,ch,n->white?2:1,attr);
    if (n->white) {
        if (n->last) rain_put(n->y-1,n->x,n->last,1,rain_attr(o,n,1));
        n->last=ch;
    }
}
static void rain_status(RainOptions *o,const char *text) {
    if (o->status_off) return;
    snprintf(o->status,sizeof(o->status),"%-11.70s",text);
    o->status_count=100/(o->delay/10+1)+2;
}
static int rain_key(RainOptions *o,int key) {
    if (key==ERR || key==KEY_RESIZE || o->ignore_keyboard) return 0;
    if (key==' ' || key=='q' || key==27) {rain_stop=1;return 1;}
    switch (key) {
    case 'a': o->asynchronous=!o->asynchronous; rain_status(o,o->asynchronous?"Async: on":"Async: off"); break;
    case 'b': o->bold=o->bold==0?1:o->bold==1?-1:0; rain_status(o,o->bold<0?"Bold: off":o->bold?"Bold: all":"Bold: on"); break;
    case 'f': o->flashers=!o->flashers; rain_status(o,o->flashers?"Flash: on":"Flash: off"); break;
    case 'o': o->status_off=!o->status_off; rain_status(o,"Status: on"); break;
    case '-': case '_': case KEY_LEFT: o->delay+=10; goto speed;
    case '=': case '+': case KEY_RIGHT: o->delay-=10; goto speed;
    case '[': case KEY_DOWN: o->delay+=100; goto speed;
    case ']': case KEY_UP: o->delay-=100; goto speed;
    default: {
        static const int colors[]={COLOR_GREEN,COLOR_RED,COLOR_BLUE,COLOR_WHITE,COLOR_YELLOW,COLOR_CYAN,COLOR_MAGENTA,COLOR_BLACK,-1};
        const char *background_keys="!@#$%^&*(";
        const char *p=(key>0 && key<128) ? strchr(background_keys,key) : NULL;
        if (key>='1' && key<='9') o->fg=colors[key-'1'];
        else if (p) o->bg=colors[p-background_keys];
        else break;
        init_pair(1,(short)o->fg,(short)o->bg); init_pair(2,COLOR_WHITE,(short)o->bg);
        rain_status(o,"Color changed");
        break;
    }
    }
    return 1;
 speed:
    if (o->delay<0) o->delay=0;
    if (o->delay>10990) o->delay=10990;
    { char text[32]; snprintf(text,sizeof(text),"Speed: %d",100-o->delay/10);rain_status(o,text); }
    return 1;
}
/* C scheduler adapted from GeertJohan/gomatrix, commit cfb8e3310c1f.
 * Copyright 2013, Geert-Johan Riemer
 * Copyright 2015, Garrett D'Amore
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 * A single deadline scheduler replaces Go goroutines, without quantizing
 * stream movement to screen refreshes. Each stream retains its own period.
 */
#define GO_MIN_LENGTH 13
#define GO_MAX_LENGTH 21
#define GO_LENGTH_LIMIT 128
#define GO_HISTORY_SIZE (GO_LENGTH_LIMIT + 1)
typedef struct {
    int x, head, tail, length, period, finished;
    wchar_t last;
    unsigned long id;
    wchar_t glyphs[GO_HISTORY_SIZE];
    unsigned char tones[GO_HISTORY_SIZE];
    double next;
} GoStream;
typedef struct {
    int rows, cols;
    double *spawn;
    unsigned long *owners, serial;
    unsigned char *bottom_seen;
    int bottom_count;
    GoStream *streams;
    size_t count, capacity;
} GoCanvas;
static void go_free(GoCanvas *c) {
    free(c->spawn);free(c->streams);free(c->owners);free(c->bottom_seen);memset(c,0,sizeof(*c));
}
static int go_canvas(GoCanvas *c,int rows,int cols,double now) {
    go_free(c);
    if(rows<1 || cols<1 || (size_t)rows*(size_t)cols>16000000)return 0;
    c->rows=rows;c->cols=cols;
    c->spawn=calloc((size_t)cols,sizeof(*c->spawn));
    c->owners=calloc((size_t)rows*(size_t)cols,sizeof(*c->owners));
    c->bottom_seen=calloc((size_t)cols,sizeof(*c->bottom_seen));
    if(!c->spawn || !c->owners || !c->bottom_seen)return 0;
    for(int x=0;x<cols;++x)c->spawn[x]=now+rain_rand(0,8999)/1000.0;
    erase();return 1;
}
static int go_spawn(GoCanvas *c,int x,double now,const RainOptions *o) {
    if(c->count==c->capacity) {
        size_t capacity=c->capacity?c->capacity*2:128;
        GoStream *streams=realloc(c->streams,capacity*sizeof(*streams));
        if(!streams)return 0;
        c->streams=streams;c->capacity=capacity;
    }
    int period=rain_rand(30,139),low=o->length_min?o->length_min:GO_MIN_LENGTH;
    int high=o->length_max?o->length_max:GO_MAX_LENGTH;
    /* Keep erasing reachable in short windows. Scale both length bounds
     * together so dashboards retain a distribution of stream lengths. */
    if(!o->length_min && c->rows<GO_MAX_LENGTH-1) {
        high=c->rows+1;low=(GO_MIN_LENGTH*high+GO_MAX_LENGTH-1)/GO_MAX_LENGTH;
        if(low<2)low=2;
    }
    int length=rain_rand(low,high);
    c->streams[c->count++]=(GoStream){.x=x,.period=period,.length=length,.id=++c->serial,
        .next=now+period/1000.0*(o->delay>0?o->delay:1)/20.0};
    c->spawn[x]=-1;
    return 1;
}
static void go_step(GoCanvas *c,GoStream *s,const RainOptions *o,double now) {
    /* Explicit panel lengths may extend beyond its visible bottom. Keep the
     * virtual head moving until its tail can enter, even outside the view. */
    if(s->head<=c->rows || (s->tail==0 && s->head<s->length)) {
        wchar_t ch=rain_char(o);
        short body=rain_rand(0,99)<66?4:5;
        if(s->last) {
            int row=s->head-1;
            s->tones[row%GO_HISTORY_SIZE]=(unsigned char)(body==5);
            if(row<c->rows && c->owners[(size_t)row*c->cols+s->x]==s->id)
                rain_put(row,s->x,s->last,body,A_NORMAL);
        }
        short head=rain_rand(0,99)<33?6:7;
        rain_put(s->head,s->x,ch,head,A_NORMAL);
        if(s->head==c->rows-1 && c->bottom_seen && !c->bottom_seen[s->x]) {
            c->bottom_seen[s->x]=1;++c->bottom_count;
        }
        s->glyphs[s->head%GO_HISTORY_SIZE]=ch;
        if(s->head<c->rows)c->owners[(size_t)s->head*c->cols+s->x]=s->id;
        s->last=ch;++s->head;
    }
    if(s->tail>0 || s->head>=s->length) {
        if(s->tail==0)c->spawn[s->x]=now+rain_rand(0,8999)/1000.0;
        if(s->tail<c->rows){
            size_t pos=(size_t)s->tail*c->cols+s->x;
            if(c->owners[pos]==s->id){rain_put(s->tail,s->x,L' ',1,A_NORMAL);c->owners[pos]=0;}
            ++s->tail;
        }
        else s->finished=1;
    }
    int fade=o->fade;
    if(fade>s->length-2)fade=s->length-2;
    /* While a new stream grows into view, its tail is still above the
     * screen. Using the eraser's initial zero here pins a dark band to the
     * first rows. Let the virtual tail follow the head until erasing starts. */
    int fade_start=s->tail>0?s->tail:s->head-s->length+1;
    /* Only touch this stream's surviving cells: a faster following stream
     * must not have its head dimmed or erased by the earlier stream's tail. */
    for(int j=0;j<fade;++j) {
        int row=fade_start+j;
        if(row<0)continue;
        if(row>=s->head-1 || row>=c->rows)break;
        if(c->owners[(size_t)row*c->cols+s->x]!=s->id)continue;
        int level=(j+1)*9/(fade+1);
        short pair=(short)(8+2*(level-1)+s->tones[row%GO_HISTORY_SIZE]);
        rain_put(row,s->x,s->glyphs[row%GO_HISTORY_SIZE],pair,A_NORMAL);
    }
    s->next=now+s->period/1000.0*(o->delay>0?o->delay:1)/20.0;
}
static void go_colors(const RainOptions *o) {
    /* Fixed 256-color values avoid a theme's green and bold substitutions.
     * They approximate Go's #008000/#00ff00/#c0c0c0/#ffffff; transparency
     * stays inherited. Sixteen/eight-color terminals degrade gracefully. */
    if(COLORS>=16777216) {
        /* Erase/background attributes can be inherited by terminal glyphs.
         * Keep that foreground in RGB too, rather than theme ANSI green. */
        init_extended_pair(1,0x008000,o->bg);
        init_extended_pair(4,0x008000,o->bg);init_extended_pair(5,0x00ff00,o->bg);
        init_extended_pair(6,0xc0c0c0,o->bg);init_extended_pair(7,0xffffff,o->bg);
        for(int level=1;level<=8;++level) {
            init_extended_pair(8+2*(level-1),(128*level/9)<<8,o->bg);
            init_extended_pair(9+2*(level-1),(255*level/9)<<8,o->bg);
        }
        return;
    }
    short dark=COLOR_GREEN,bright=COLORS>=16?10:COLOR_GREEN;
    short silver=COLOR_WHITE,white=COLORS>=16?15:COLOR_WHITE;
    if(COLORS>=256){dark=28;bright=46;silver=250;white=231;}
    init_pair(1,dark,(short)o->bg);
    init_pair(4,dark,(short)o->bg);init_pair(5,bright,(short)o->bg);
    init_pair(6,silver,(short)o->bg);init_pair(7,white,(short)o->bg);
    for(int level=1;level<=8;++level) {
        short dim_dark=dark,dim_bright=bright;
        if(COLORS>=256) {
            int a=(128*level/9),b=(255*level/9);
            dim_dark=(short)(16+6*(a*5/255));dim_bright=(short)(16+6*(b*5/255));
        }
        init_pair((short)(8+2*(level-1)),dim_dark,(short)o->bg);
        init_pair((short)(9+2*(level-1)),dim_bright,(short)o->bg);
    }
}
/* Advance without presenting intermediate frames, so the opening can begin
 * with an already established rain pattern. Normal mode keeps its own loop. */
static int go_advance(GoCanvas *c,const RainOptions *o,double target) {
    for(;;) {
        double next=target+1.0;
        int spawn=-1;size_t stream=c->count;
        for(int x=0;x<c->cols;++x) {
            if(c->spawn[x]>=0 && c->spawn[x]<next) {
                next=c->spawn[x];spawn=x;stream=c->count;
            }
        }
        for(size_t i=0;i<c->count;++i) {
            if(c->streams[i].next<next) {
                next=c->streams[i].next;stream=i;spawn=-1;
            }
        }
        if(next>target)return 1;
        if(spawn>=0) {
            if(!go_spawn(c,spawn,next,o))return 0;
        } else if(stream<c->count) {
            go_step(c,&c->streams[stream],o,next);
            if(c->streams[stream].finished)c->streams[stream]=c->streams[--c->count];
        }
    }
}
static int go_run(RainOptions *o) {
    GoCanvas canvas={0};
    WINDOW *input=newwin(1,1,0,0);
    if(!input)return 1;
    keypad(input,TRUE);nodelay(input,TRUE);untouchwin(input);
    go_colors(o);
    double start=rain_time(),frame=start;
    int initial_fps=o->fps,exit_code=0;
    double playback_rate=o->intro?2.5:1.0,simulation_start=start;
    if(!go_canvas(&canvas,LINES,COLS,start)){exit_code=1;goto finish;}
    if(o->intro) {
        /* Select a middle frame offscreen. Every column has had time to
         * reach the bottom at least once; only the resulting frame is shown. */
        simulation_start=start+9.0+canvas.rows*0.139;
        if(!go_advance(&canvas,o,simulation_start)){exit_code=1;goto finish;}
        start=rain_time();frame=start;
    }
    while(!rain_stop) {
        double wall=rain_time();
        double now=wall;
        if(o->intro)now=simulation_start+(wall-start)*playback_rate;
        if(o->runtime>0 && wall-start>=o->runtime)break;
        /* Reading a separate untouched window avoids wgetch's implicit
         * refresh of stdscr, so --fps really controls visible flushes. */
        int key=wgetch(input),reset=0;
        if(!o->ignore_keyboard && key!=ERR && key!=KEY_RESIZE) {
            switch(key) {
            case 'q':case ' ':case 27:rain_stop=1;break;
            case 'k':o->char_count=0;rain_append(o,go_kana);break;
            case 'b':o->char_count=0;rain_append(o,go_kana);rain_append(o,go_alphanumerics);break;
            case 'c':reset=1;break;
            case '+':if(o->fps<120)++o->fps;frame=wall;break;
            case '-':if(o->fps>1)--o->fps;frame=wall;break;
            case '=':o->fps=initial_fps;frame=wall;break;
            default:break;
            }
        }
        if(canvas.rows!=LINES || canvas.cols!=COLS || reset) {
            if(!go_canvas(&canvas,LINES,COLS,now)){exit_code=1;break;}
            untouchwin(input);frame=wall;
        }
        if(o->intro) {
            if(!go_advance(&canvas,o,now)){exit_code=1;break;}
        } else {
            for(int x=0;x<canvas.cols;++x)
                if(canvas.spawn[x]>=0 && canvas.spawn[x]<=now && !go_spawn(&canvas,x,now,o)) {
                    exit_code=1;rain_stop=1;break;
                }
            for(size_t i=0;i<canvas.count;++i)
                if(canvas.streams[i].next<=now)go_step(&canvas,&canvas.streams[i],o,now);
        }
        size_t kept=0;
        for(size_t i=0;i<canvas.count;++i)
            if(!canvas.streams[i].finished)canvas.streams[kept++]=canvas.streams[i];
        canvas.count=kept;
        if(wall>=frame){refresh();frame=wall+1.0/o->fps;}
        /* Wake only for input polling, a stream step, spawn or refresh. */
        double next=now+0.020;
        for(int x=0;x<canvas.cols;++x)
            if(canvas.spawn[x]>=0 && canvas.spawn[x]<next)next=canvas.spawn[x];
        for(size_t i=0;i<canvas.count;++i)
            if(canvas.streams[i].next<next)next=canvas.streams[i].next;
        wall=rain_time();
        double remaining;
        if(o->intro) {
            remaining=frame-wall;
            if(remaining>0.020)remaining=0.020;
            double current=simulation_start+(wall-start)*playback_rate;
            double event_wait=(next-current)/playback_rate;
            if(event_wait<remaining)remaining=event_wait;
        } else {
            if(frame<next)next=frame;
            remaining=next-wall;
        }
        if(remaining>0)matrix_sleep_seconds(remaining);
    }
 finish:
    delwin(input);go_free(&canvas);return exit_code;
}
static void rain_help(void) {
    puts("cmatrix-uni: native half-width Unicode rain\n"
         "  -o hide status  -s SPEED (-999..100; default 85)\n"
         "  -l SETS (g=Gomatrix's 125 runes, k=kana, m=Matrix mix, o=ASCII, n/a/A/s/S/u)\n"
         "  -a asynchronous  -b all bold  -n no bold  -f flashers\n"
         "  -c COLOR foreground  -g COLOR background (default: terminal)\n"
         "  -u UTF8 custom single-cell characters  -t SECONDS runtime\n"
         "  -w single wave  -i ignore keyboard  -h help\n"
         "  --gomatrix: per-stream 30..139ms steps, 13..21 length, 0..8999ms gaps;\n"
         "    white/silver heads, two greens, all columns, default -l g and -s 98.\n"
         "    Short windows scale lengths; --fps 1..120 (default 60) only controls refresh.\n"
         "    --fade 0..8 (default 4) dims the tail; 0 restores Go's hard erase.\n"
         "    --intro starts from an established rain frame at a constant 2.5x speed.\n"
         "    --length MIN:MAX sets 2..128 cells, even beyond a short panel's height.\n"
         "    cmatrix-gm starts this style directly, e.g. cmatrix-gm --fade 6.\n"
         "    Keys: k kana, b both, c clear, +/- fps, = restore fps, q/Esc/space quit.\n"
         "  Keys: q/Esc/space quit, +/- and [] speed, a/b/f/o toggles, 1..9 colors.\n"
         "  cmatrix-uni is the dedicated entry; cmatrix keeps its original defaults.");
}
int unimatrix_main(int argc,char **argv) {
    RainOptions o={.delay=150,.fg=COLOR_GREEN,.bg=-1,.fps=60,.fade=4};
    RainCanvas canvas={0};
    wchar_t custom[8192]=L"";
    const char *letters=NULL,*custom_utf8=NULL;
    int opt,no_bold=0,exit_code=0,speed_given=0,fps_given=0,fade_given=0;
    static const struct option long_options[]={
        {"gomatrix",no_argument,NULL,1000},{"fps",required_argument,NULL,1001},
        {"fade",required_argument,NULL,1002},
        {"intro",no_argument,NULL,1003},{"length",required_argument,NULL,1004},
        {"help",no_argument,NULL,'h'},{NULL,0,NULL,0}
    };
    if (!setlocale(LC_ALL,".UTF8")) {fputs("Cannot initialize locale\n",stderr);return 2;}
    optind=1; opterr=0;
    while ((opt=getopt_long(argc,argv,"abfc:g:hil:nos:t:u:w",long_options,NULL))!=-1) {
        switch(opt) {
        case 1000:o.gomatrix=1;break;
        case 1001:{char *end;long fps=strtol(optarg,&end,10);if(end==optarg || *end || fps<1 || fps>120){fputs("FPS must be 1..120\n",stderr);return 2;}o.fps=(int)fps;fps_given=1;break;}
        case 1002:{char *end;long fade=strtol(optarg,&end,10);if(end==optarg || *end || fade<0 || fade>8){fputs("Fade must be 0..8\n",stderr);return 2;}o.fade=(int)fade;fade_given=1;break;}
        case 1003:o.intro=1;break;
        case 1004: {
            char *middle,*end;long low=strtol(optarg,&middle,10);
            if(middle==optarg || *middle!=':'){fputs("Length must be MIN:MAX within 2..128\n",stderr);return 2;}
            long high=strtol(middle+1,&end,10);
            if(end==middle+1 || *end || low<2 || high<low || high>GO_LENGTH_LIMIT){fputs("Length must be MIN:MAX within 2..128\n",stderr);return 2;}
            o.length_min=(int)low;o.length_max=(int)high;break;
        }
        case 'a':o.asynchronous=1;break; case 'b':o.bold=1;break;
        case 'f':o.flashers=1;break; case 'i':o.ignore_keyboard=1;break;
        case 'n':no_bold=1;break;case 'o':o.status_off=1;break;
        case 'w':o.single_wave=1;break;case 'l':letters=optarg;break;
        case 's': {
            char *end;long speed=strtol(optarg,&end,10);
            if (*end || speed>100 || speed< -999) {fputs("Speed must be -999..100\n",stderr);return 2;}
            o.delay=(100-(int)speed)*10;speed_given=1;break;
        }
        case 't':{char *end;o.runtime=strtod(optarg,&end);if(*end || o.runtime<=0){fputs("Runtime must be positive\n",stderr);return 2;}break;}
        case 'c':case 'g':{
            int color=rain_color(optarg);if(color==INT_MIN){fputs("Unknown color\n",stderr);return 2;}
            if(opt=='c')o.fg=color;else o.bg=color;break;
        }
        case 'u':custom_utf8=optarg;break;
        case 'h':rain_help();return 0;
        default:rain_help();return 2;
        }
    }
    if (optind<argc) {fputs("Unexpected argument\n",stderr);return 2;}
    if(fps_given && !o.gomatrix){fputs("--fps requires --gomatrix\n",stderr);return 2;}
    if(fade_given && !o.gomatrix){fputs("--fade requires --gomatrix\n",stderr);return 2;}
    if((o.intro || o.length_min) && !o.gomatrix){fputs("--intro/--length require --gomatrix\n",stderr);return 2;}
    if(o.gomatrix && (o.single_wave || o.flashers || o.bold || no_bold || o.fg!=COLOR_GREEN)) {
        fputs("--gomatrix uses its own brightness; -w/-f/-b/-n/-c belong to the Unimatrix mode\n",stderr);return 2;
    }
    if(o.gomatrix && !speed_given)o.delay=20;
    if (custom_utf8 && mbstowcs(custom,custom_utf8,sizeof(custom)/sizeof(*custom)-1)==(size_t)-1) {fputs("Custom characters require a UTF-8 locale\n",stderr);return 2;}
    if (!letters) letters=custom_utf8?"u":o.gomatrix?"g":"m";
    if (!rain_charset(&o,letters,custom)) {fputs("Unsupported charset or non-single-cell character; use -l k/m/o/n/a/A/s/S/u\n",stderr);return 2;}
    if (no_bold)o.bold=-1;
    srand((unsigned)time(NULL)^(unsigned)getpid());
    rain_stop=0;matrix_set_stop_flag(&rain_stop);
    /* Use semicolon RGB SGRs (38;2;r;g;b). xterm-direct's double-colon color
     * space field is misread by the embedded libvterm in current Neovim.
     * Keep the normal terminal entry if direct-color data is unavailable. */
    SCREEN *direct=NULL;
    const char *terminal=getenv("TERM");
    if(o.gomatrix && terminal && strcmp(terminal,"dumb") && strcmp(terminal,"linux"))
        direct=newterm("vte-direct",stdout,stdin);
    if(!direct)initscr();
    cbreak();noecho();keypad(stdscr,TRUE);nodelay(stdscr,TRUE);curs_set(0);
    start_color();use_default_colors();init_pair(1,(short)o.fg,(short)o.bg);init_pair(2,COLOR_WHITE,(short)o.bg);init_pair(3,COLOR_BLACK,COLOR_WHITE);
    bkgd(COLOR_PAIR(1));
    signal(SIGINT,rain_signal);signal(SIGTERM,rain_signal);
    if(o.gomatrix){exit_code=go_run(&o);goto finish;}
    double start=rain_time();int async_clock=5,wave_delay=o.single_wave?10:0;
    if (!rain_canvas(&canvas,LINES,COLS,&o)) {exit_code=1;goto finish;}
    while (!rain_stop) {
        if (o.runtime>0 && rain_time()-start>o.runtime) break;
        int key=getch();
        if (rain_key(&o,key))continue;
        if (canvas.rows!=LINES || canvas.cols!=COLS) {
            if(!rain_canvas(&canvas,LINES,COLS,&o)){exit_code=1;break;}async_clock=5;
        }
        for(int i=0;i<canvas.column_count;++i) {
            RainColumn *col=&canvas.columns[i];
            if(col->timer==0 && !rain_spawn(&canvas,col,&o)){rain_stop=1;exit_code=1;break;}
            --col->timer;
        }
        for(size_t i=0;i<canvas.count;++i) {
            RainNode *node=&canvas.nodes[i];
            if (o.flashers && node->y>=0 && node->y<canvas.rows) {
                size_t pos=(size_t)node->y*canvas.cols+node->x;
                if(node->writer && !rain_rand(0,9))canvas.flashers[pos]=1;
                else if(!node->writer)canvas.flashers[pos]=0;
            }
            if(!o.asynchronous || async_clock%node->speed==0){rain_draw(node,&o);++node->y;}
            if(node->y>=canvas.rows){if(node->white){node->white=0;--node->y;}else node->expired=1;}
        }
        if(o.flashers && async_clock%3==0) {
            for(int y=0;y<canvas.rows;++y)for(int x=0;x<canvas.cols;x+=2)
                if(canvas.flashers[(size_t)y*canvas.cols+x]) {
                    attr_t attr=rain_rand(0,1)==0?A_BOLD:A_NORMAL;
                    wchar_t character=rain_char(&o);
                    rain_put(y,x,character,1,attr);
                }
        }
        size_t kept=0;
        for(size_t i=0;i<canvas.count;++i)if(!canvas.nodes[i].expired)canvas.nodes[kept++]=canvas.nodes[i];
        canvas.count=kept;
        if(o.single_wave && !canvas.count && wave_delay<0)break;
        if(o.single_wave)--wave_delay;
        if(o.status_count>0){attron(COLOR_PAIR(3));mvaddnstr(0,0,o.status,o.status_count==1?0:11);attroff(COLOR_PAIR(3));if(o.status_count==1)mvaddstr(0,0,"           ");--o.status_count;}
        refresh();napms(o.delay);async_clock=async_clock?async_clock-1:5;
    }
 finish:
    rain_free(&canvas);curs_set(1);endwin();if(direct)delscreen(direct);return exit_code;
}
