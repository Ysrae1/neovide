#!/usr/bin/env python3
"""Real macOS native-menu en -> zh -> en regression, using only owned processes.

Run with the existing Notebook Python (pynvim); an existing installation is also
auto-detected. Requires Xcode command-line tools. Without existing Accessibility
authorization, a test-only dylib observes AppKit inside our own frontend process.
No authorization prompt is requested; a hardened binary may reject injection.

  python3 tests/macos/native_menu_language.py \
    --binary /absolute/development/Neovide.app/Contents/MacOS/neovide \
    --config ~/.config/nvim --output /absolute/QA/native-menu-local-1

The actual config is copied, existing plugins are reused, and state/data/cache
are isolated. Plugin installation and updates are disabled. Only temporary text
fixtures are edited. Logs, menu snapshots, document snapshots and receipt.json
are retained. This test does not install a build or inspect other editors.
The in-process fallback also observes the actual delegate's Dock menu without
opening a Dock tile. Neither observer changes titles or introduces a debug RPC.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import traceback


# AXIsProcessTrusted() deliberately does not request permission. Never use a
# global keystroke, process-name activation, or a menu action that opens files.
AX_SOURCE = r'''
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

static id Attr(AXUIElementRef element, CFStringRef name) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, name, &value) != kAXErrorSuccess)
        return nil;
    return CFBridgingRelease(value);
}
static NSArray *Children(AXUIElementRef element) {
    id value = Attr(element, kAXChildrenAttribute);
    return [value isKindOfClass:NSArray.class] ? value : @[];
}
static NSDictionary *Read(AXUIElementRef element, int depth) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"AXRole", @"AXTitle", @"AXIdentifier",
                            @"AXMenuItemCmdChar", @"AXMenuItemCmdModifiers",
                            @"AXMenuItemCmdVirtualKey", @"AXMenuItemCmdGlyph"]) {
        id value = Attr(element, (__bridge CFStringRef)key);
        if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class])
            result[key] = value;
    }
    if (depth > 0) {
        NSMutableArray *children = [NSMutableArray array];
        for (id child in Children(element)) {
            if (children.count >= 120) break;
            [children addObject:Read((__bridge AXUIElementRef)child, depth - 1)];
        }
        result[@"children"] = children;
    }
    return result;
}
static void Emit(NSDictionary *result) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (!AXIsProcessTrusted()) {
            Emit(@{@"error": @"Accessibility authorization unavailable; no prompt requested"});
            return 77;
        }
        if (argc == 2 && strcmp(argv[1], "--check") == 0) {
            Emit(@{@"trusted": @YES}); return 0;
        }
        if (argc != 2) return 2;
        pid_t pid = (pid_t)strtol(argv[1], NULL, 10);
        if (pid <= 1) return 2;
        NSRunningApplication *target = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        if (!target || target.terminated) {
            Emit(@{@"error": @"Owned application PID is not running"}); return 3;
        }
        // Activation is always by the exact child PID supplied by the harness.
        [target activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        AXUIElementRef app = AXUIElementCreateApplication(pid);
        AXUIElementSetMessagingTimeout(app, 0.75);
        id bar = Attr(app, kAXMenuBarAttribute);
        if (!bar) {
            Emit(@{@"error": @"Owned application has no accessible menu bar"});
            CFRelease(app); return 4;
        }
        NSMutableArray *menus = [NSMutableArray array];
        for (id top in Children((__bridge AXUIElementRef)bar)) {
            AXUIElementRef item = (__bridge AXUIElementRef)top;
            // Open only the owned app's top-level menus to materialize AppKit
            // entries, then cancel without invoking any menu-item command.
            AXError opened = AXUIElementPerformAction(item, kAXPressAction);
            [NSThread sleepForTimeInterval:0.04];
            [menus addObject:Read(item, 3)];
            if (opened == kAXErrorSuccess) {
                AXError cancelled = kAXErrorActionUnsupported;
                for (id menu in Children(item)) {
                    cancelled = AXUIElementPerformAction((__bridge AXUIElementRef)menu, kAXCancelAction);
                    if (cancelled == kAXErrorSuccess) break;
                }
                if (cancelled != kAXErrorSuccess)
                    cancelled = AXUIElementPerformAction(item, kAXCancelAction);
                if (cancelled != kAXErrorSuccess) {
                    // Pressing the same top-level item closes its own menu.
                    AXUIElementPerformAction(item, kAXPressAction);
                }
            }
        }
        NSMutableArray *windows = [NSMutableArray array];
        id windowList = Attr(app, kAXWindowsAttribute);
        if ([windowList isKindOfClass:NSArray.class]) {
            for (id window in windowList) [windows addObject:Read((__bridge AXUIElementRef)window, 0)];
        }
        Emit(@{@"pid": @(pid), @"menus": menus, @"windows": windows});
        CFRelease(app);
    }
    return 0;
}
'''


OBSERVER_SOURCE = r'''
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#import <unistd.h>

static NSString *Root;
static NSString *LastToken;
static NSString *PendingToken;
static NSString *Identity(id object) {
    return object ? [NSString stringWithFormat:@"%p", (__bridge void *)object] : @"nil";
}
static NSDictionary *ReadMenu(NSMenu *menu, int depth);
static NSDictionary *ReadItem(NSMenuItem *item, int depth, BOOL top) {
    NSMutableDictionary *row = [@{@"AXRole": top ? @"AXMenuBarItem" : @"AXMenuItem",
        @"AXTitle": item.title ?: @"", @"identity": Identity(item),
        @"selector": item.action ? NSStringFromSelector(item.action) : @"",
        @"target": Identity(item.target),
        @"identifier": item.identifier ?: @"",
        @"AXMenuItemCmdChar": item.keyEquivalent ?: @"",
        @"AXMenuItemCmdModifiers": @(item.keyEquivalentModifierMask)} mutableCopy];
    if (@available(macOS 14.0, *)) row[@"isSectionHeader"] = @(item.sectionHeader);
    row[@"children"] = item.submenu && depth > 0 ? @[ReadMenu(item.submenu, depth - 1)] : @[];
    return row;
}
static NSDictionary *ReadMenu(NSMenu *menu, int depth) {
    NSMutableArray *rows = [NSMutableArray array];
    if (depth > 0) for (NSMenuItem *item in menu.itemArray) {
        if (rows.count >= 120) break;
        [rows addObject:ReadItem(item, depth - 1, NO)];
    }
    return @{@"AXRole": @"AXMenu", @"AXTitle": menu.title ?: @"",
        @"identity": Identity(menu), @"delegate": Identity(menu.delegate), @"children": rows};
}
static void Write(NSString *name, NSDictionary *value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    [data writeToFile:[Root stringByAppendingPathComponent:name] options:NSDataWritingAtomic error:nil];
}
static void Observe(void) {
    @try {
        NSData *data = [NSData dataWithContentsOfFile:[Root stringByAppendingPathComponent:@"request.json"]];
        NSDictionary *request = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *token = request[@"token"];
        if (![token isKindOfClass:NSString.class] || token.length == 0 || [token isEqual:LastToken]) return;
        // Tokens are generated by this test, and cannot select arbitrary paths.
        if ([token rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789-"] invertedSet]].location != NSNotFound) return;
        if (!NSApp.mainMenu) return;
        if (![token isEqual:PendingToken]) {
            PendingToken = [token copy];
            for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
                NSMenu *menu = top.submenu;
                if ([menu.delegate respondsToSelector:@selector(menuNeedsUpdate:)])
                    [menu.delegate menuNeedsUpdate:menu];
                [menu update];
                if ([menu.delegate respondsToSelector:@selector(menuWillOpen:)])
                    [menu.delegate menuWillOpen:menu];
            }
            // Return to the main run loop. Its pending common-mode production
            // timer must run before the next observer tick takes the snapshot.
            return;
        }
        NSMutableArray *menus = [NSMutableArray array];
        for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
            // Snapshot phase is read-only: never validate again here.
            [menus addObject:ReadItem(top, 5, YES)];
        }
        NSMutableArray *windows = [NSMutableArray array];
        NSMutableArray *helpers = [NSMutableArray array];
        for (NSWindow *window in NSApp.windows) {
            NSDictionary *row = @{@"AXRole": @"AXWindow", @"AXTitle": window.title ?: @"",
                                  @"identity": Identity(window)};
            // AppKit may lazily create empty-title helper windows during menu
            // validation. Our named document windows retain their full identity
            // and title invariant; helpers remain visible in the evidence.
            [(window.title.length > 0 ? windows : helpers) addObject:row];
        }
        NSMutableDictionary *snapshot = [@{@"pid": @(getpid()), @"menus": menus, @"windows": windows,
            @"observer_phase": @"after-menu-open-deferred",
            @"fullscreen": @((NSApp.keyWindow.styleMask & NSWindowStyleMaskFullScreen) != 0),
            @"helper_windows": helpers,
            @"registrations": @{@"main": Identity(NSApp.mainMenu), @"services": Identity(NSApp.servicesMenu),
                                 @"windows": Identity(NSApp.windowsMenu), @"help": Identity(NSApp.helpMenu)}} mutableCopy];
        id delegate = NSApp.delegate;
        if ([delegate respondsToSelector:@selector(applicationDockMenu:)]) {
            NSMenu *dock = [delegate applicationDockMenu:NSApp];
            if (dock) snapshot[@"dock"] = ReadMenu(dock, 3);
        }
        Write([token stringByAppendingString:@".json"], snapshot);
        LastToken = [token copy];
        PendingToken = nil;
    } @catch (NSException *exception) {
        Write(@"observer-error.json", @{@"error": exception.reason ?: @"AppKit observer exception"});
    }
}
__attribute__((constructor)) static void StartObserver(void) {
    @autoreleasepool {
        const char *path = getenv("GLOW_MENU_OBSERVER_DIR");
        if (!path) return;
        Root = [NSString stringWithUTF8String:path];
        dispatch_async(dispatch_get_main_queue(), ^{
            Write(@"loaded.json", @{@"pid": @(getpid()), @"observer": @"AppKit objects in owned process"});
            [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) { Observe(); }];
        });
    }
}
'''


SNAPSHOT = r'''
local buffers = {}
for _,b in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted then
    buffers[#buffers+1] = {id=b, name=vim.api.nvim_buf_get_name(b),
      lines=vim.api.nvim_buf_get_lines(b,0,-1,false),
      tick=vim.api.nvim_buf_get_changedtick(b), modified=vim.bo[b].modified,
      undo=vim.api.nvim_buf_call(b,function() return vim.fn.undotree() end)}
  end
end
local windows = {}
for _,w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.api.nvim_win_get_config(w).relative == '' then
    windows[#windows+1] = {id=w, buffer=vim.api.nvim_win_get_buf(w),
      cursor=vim.api.nvim_win_get_cursor(w),
      view=vim.api.nvim_win_call(w,function() return vim.fn.winsaveview() end)}
  end
end
return {buffers=buffers, windows=windows, layout=vim.fn.winlayout(),
  current_buffer=vim.api.nvim_get_current_buf(), current_window=vim.api.nvim_get_current_win(),
  current_tab=vim.api.nvim_get_current_tabpage(), tabs=vim.api.nvim_list_tabpages()}
'''


# Deliberately avoids nvim_buf_call/nvim_win_call so the diagnostic can detect
# whether the fuller document snapshot itself changes window/cursor state.
CURSORS = r'''
local windows={}
for _,win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.api.nvim_win_get_config(win).relative=='' then
    windows[#windows+1]={id=win,buffer=vim.api.nvim_win_get_buf(win),
      cursor=vim.api.nvim_win_get_cursor(win),width=vim.api.nvim_win_get_width(win),
      height=vim.api.nvim_win_get_height(win)}
  end
end
return {windows=windows,lines=vim.o.lines,columns=vim.o.columns,
  current_window=vim.api.nvim_get_current_win(),current_buffer=vim.api.nvim_get_current_buf(),
  mode=vim.api.nvim_get_mode()}
'''


def pynvim_module():
    try:
        import pynvim
        return pynvim
    except ImportError:
        candidate = Path.home() / '.local/share/nvim/glow-notebook-venv/bin/python'
        if candidate.is_file() and not os.environ.get('GLOW_MENU_PYTHON_REEXEC'):
            os.environ['GLOW_MENU_PYTHON_REEXEC'] = '1'
            os.execv(str(candidate), [str(candidate), str(Path(__file__).resolve()), *sys.argv[1:]])
        raise SystemExit('pynvim is required; use the existing Notebook venv Python')


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def descendants(node):
    yield node
    for child in node.get('children', []):
        yield from descendants(child)


def menu_rows(snapshot, language):
    labels = {
        'en': {'edit': 'Edit', 'window': 'Window', 'help': 'Help', 'copy': 'Copy',
               'new': 'New Window', 'editors': 'Editors', 'minimize': 'Minimize',
               'issue': 'Create Issue Report', 'docs': 'Documentation', 'sponsor': 'Sponsor'},
        'zh': {'edit': '编辑', 'window': '窗口', 'help': '帮助', 'copy': '复制',
               'new': '新建窗口', 'editors': '编辑器', 'minimize': '最小化',
               'issue': '报告问题', 'docs': '使用文档', 'sponsor': '赞助'},
    }[language]
    top = {node.get('AXTitle'): node for node in snapshot['menus']}
    for key in ('edit', 'window', 'help'):
        assert labels[key] in top, ('missing native top menu', language, labels[key], list(top))
    result = {}
    for group, keys in (('edit', ('copy',)),
                        ('window', ('new', 'editors', 'minimize')),
                        ('help', ('issue', 'docs', 'sponsor'))):
        rows = {node.get('AXTitle'): node for node in descendants(top[labels[group]])}
        for key in keys:
            assert labels[key] in rows, ('missing actual native item', language, labels[key], list(rows))
            result[key] = rows[labels[key]]
    titles = [node.get('AXTitle', '') for menu in snapshot['menus'] for node in descendants(menu)]
    fullscreen = ('Enter Full Screen', 'Exit Full Screen') if language == 'en' else ('进入全屏', '退出全屏')
    assert any(title in fullscreen for title in titles), ('fullscreen label', language, titles)
    prefixes = ('About ', 'Hide ', 'Quit ') if language == 'en' else ('关于 ', '隐藏 ', '退出 ')
    assert all(any(title.startswith(prefix) for title in titles) for prefix in prefixes), (language, titles)
    for title in (('Services', 'Hide Others') if language == 'en' else ('服务', '隐藏其他应用')):
        assert title in titles, ('application menu label', language, title)
    return result


def system_window_rows(snapshot, language):
    """Check real observed system actions, allowing older OSes to omit them."""
    pairs = {
        '_zoomFill:': ('Fill', '填充'), '_zoomCenter:': ('Center', '居中'),
        '_zoomLeft:': ('Left', '左半屏'), '_zoomRight:': ('Right', '右半屏'),
        '_zoomTop:': ('Top', '上半屏'), '_zoomBottom:': ('Bottom', '下半屏'),
        '_zoomTopLeft:': ('Top Left', '左上'), '_zoomTopRight:': ('Top Right', '右上'),
        '_zoomBottomLeft:': ('Bottom Left', '左下'), '_zoomBottomRight:': ('Bottom Right', '右下'),
        '_zoomLeftAndRight:': ('Left & Right', '左侧与右侧'),
        '_zoomLeftThreeUp:': ('Left & Quarters', '左侧与四分屏'),
        '_zoomRightAndLeft:': ('Right & Left', '右侧与左侧'),
        '_zoomRightThreeUp:': ('Right & Quarters', '右侧与四分屏'),
        '_zoomTopAndBottom:': ('Top & Bottom', '顶部与底部'),
        '_zoomTopThreeUp:': ('Top & Quarters', '顶部与四分屏'),
        '_zoomBottomAndTop:': ('Bottom & Top', '底部与顶部'),
        '_zoomBottomThreeUp:': ('Bottom & Quarters', '底部与四分屏'),
        '_zoomQuarters:': ('Quarters', '四分屏'), '_zoomUntile:': ('Return to Previous Size', '恢复上次大小'),
        '_tileLeft:': ('Left of Screen', '屏幕左侧'), '_tileRight:': ('Right of Screen', '屏幕右侧'),
        '_removeWindowFromStageManagerSet:': ('Remove Window from Set', '从窗口组移除'),
        'miniaturizeAll:': ('Minimize All', '最小化所有窗口'),
        'selectPreviousTab:': ('Show Previous Tab', '显示上一个标签页'),
        'selectNextTab:': ('Show Next Tab', '显示下一个标签页'),
        'moveTabToNewWindow:': ('Move Tab to New Window', '将标签页移到新窗口'),
        'arrangeInFront:': ('Bring All to Front', '全部前置'),
    }
    sections = [('Move & Resize', '移动与调整大小'), ('Full Screen Tile', '全屏拼排'),
                ('Halves', '半屏'), ('Quarters', '四分屏'), ('Arrange', '排列')]
    index = language == 'zh'
    menu = next(node for node in snapshot['menus'] if node.get('AXTitle') == ('窗口' if index else 'Window'))
    known, unknown, devices = {}, {}, []
    fullscreen_count = 0
    for node in descendants(menu):
        if node.get('AXRole') not in ('AXMenuItem', 'AXMenuBarItem'):
            continue
        action, title = node.get('selector', ''), node.get('AXTitle', '')
        if action in pairs:
            assert title == pairs[action][index], ('system operation title', language, action, title)
        elif action == 'toggleFullScreen:':
            expected = ('Exit Full Screen' if snapshot['fullscreen'] else 'Enter Full Screen',
                        '退出全屏' if snapshot['fullscreen'] else '进入全屏')[index]
            assert title == expected, ('every fullscreen action must match state/language', title, expected)
            fullscreen_count += 1
        elif action == '_toggleIPad:':
            prefix = '移到 ' if index else 'Move to '
            assert title.startswith(prefix), ('device operation prefix', language, title)
            devices.append(title[len(prefix):])
        elif action and action != 'submenuAction:' and not action.startswith('neovide') and action != 'performMiniaturize:':
            unknown[node['identity']] = {'selector': action, 'title': title}
        if action in pairs or action in ('toggleFullScreen:', '_toggleIPad:'):
            known[node['identity']] = {field: node.get(field) for field in
                                      ('selector', 'target', 'AXMenuItemCmdChar', 'AXMenuItemCmdModifiers')}
        if node.get('isSectionHeader') or action == 'submenuAction:':
            for pair in sections:
                if title in pair:
                    assert title == pair[index], ('system section title', language, title, pair[index])
    assert fullscreen_count > 0, 'no actual fullscreen menu action was observed'
    return {'known': known, 'unknown': unknown, 'device_suffixes': sorted(devices),
            'fullscreen_items': fullscreen_count}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--nvim', default=shutil.which('nvim'))
    parser.add_argument('--plugin-root', type=Path, default=Path.home() / '.local/share/nvim/lazy')
    parser.add_argument('--timeout', type=float, default=25)
    parser.add_argument('--visual-hold', type=float, default=0,
                        help='after automatic checks, hold Chinese UI for 0..60 seconds or until output/visual-done exists')
    args = parser.parse_args()
    if sys.platform != 'darwin':
        parser.error('requires native macOS')
    if not args.binary.is_absolute() or not args.output.is_absolute():
        parser.error('--binary and --output must be absolute paths')
    binary, config = args.binary.expanduser().resolve(strict=True), args.config.expanduser().resolve(strict=True)
    if binary == Path.home() / '.cargo/bin/neovide' or Path('/Applications') in binary.parents:
        parser.error('use an uninstalled development build')
    if not args.nvim or not (config / 'init.lua').is_file():
        parser.error('existing Neovim and a real config/init.lua are required')
    plugin_root = args.plugin_root.expanduser().resolve(strict=True)
    for name in ('lazy.nvim', 'LazyVim', 'base46', 'nvim-treesitter'):
        if not (plugin_root / name).is_dir():
            parser.error('missing existing plugin: ' + name)
    if not 1 <= args.timeout <= 60:
        parser.error('--timeout must be between 1 and 60 seconds')
    if not 0 <= args.visual_hold <= 60:
        parser.error('--visual-hold must be between 0 and 60 seconds')
    pynvim = pynvim_module()
    work = args.output.expanduser().resolve()
    work.mkdir(parents=True, exist_ok=False)
    # Short socket paths avoid the macOS sockaddr_un limit even for long QA paths.
    runtime = Path(tempfile.mkdtemp(prefix='glow-native-menu-'))
    socket = runtime / 'nvim.sock'
    receipt = {'status': 'starting', 'binary': str(binary), 'config': str(config),
               'output': str(work), 'socket': str(socket), 'checks': {},
               'limitations': ['Object snapshots establish live AppKit state; visual appearance needs a separate GUI inspection.']}
    processes, logs, editor = [], [], None
    done = threading.Event()

    def save():
        write_json(work / 'receipt.json', receipt)

    def stop_owned():
        # Each process is its own new session; include only its own descendants.
        for process in reversed(processes):
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        for process in reversed(processes):
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=2)

    def watchdog():
        if not done.wait(120 + args.visual_hold):
            receipt['watchdog_timeout'] = True
            stop_owned()

    def wait(predicate, description):
        deadline = time.monotonic() + args.timeout
        last = None
        while time.monotonic() < deadline:
            if any(process.poll() is not None for process in processes):
                raise AssertionError(description + ': owned process exited; inspect logs')
            last = predicate()
            if last:
                return last
            time.sleep(.1)
        raise AssertionError(description + ': timed out; last=' + repr(last))

    save()
    try:
        helper_source, helper = work / 'menu_ax.m', work / 'menu_ax'
        helper_source.write_text(AX_SOURCE)
        compile_result = subprocess.run(
            ['xcrun', 'clang', '-fobjc-arc', '-Wno-deprecated-declarations', str(helper_source),
             '-framework', 'AppKit', '-framework', 'ApplicationServices', '-o', str(helper)],
            capture_output=True, text=True, timeout=35)
        (work / 'helper-build.log').write_text(compile_result.stdout + compile_result.stderr)
        assert compile_result.returncode == 0, 'AX helper compilation failed; see helper-build.log'
        trusted = subprocess.run([str(helper), '--check'], capture_output=True, text=True, timeout=5)
        write_json(work / 'accessibility.json', {'returncode': trusted.returncode, 'stdout': trusted.stdout, 'stderr': trusted.stderr})
        observer = None
        observer_dir = work / 'appkit-observer'
        if trusted.returncode == 77:
            observer_dir.mkdir()
            observer_source, observer = work / 'menu_observer.m', work / 'menu_observer.dylib'
            observer_source.write_text(OBSERVER_SOURCE)
            compiled = subprocess.run(
                ['xcrun', 'clang', '-dynamiclib', '-fobjc-arc', '-fblocks', '-Wno-deprecated-declarations',
                 str(observer_source), '-framework', 'AppKit', '-o', str(observer)],
                capture_output=True, text=True, timeout=35)
            (work / 'observer-build.log').write_text(compiled.stdout + compiled.stderr)
            assert compiled.returncode == 0, 'AppKit observer compilation failed; see observer-build.log'
            receipt['observation_mode'] = 'owned-process-AppKit-dylib'
        else:
            assert trusted.returncode == 0, 'AX helper failed unexpectedly; see accessibility.json'
            receipt['observation_mode'] = 'accessibility'
            receipt['limitations'].append('AX mode cannot inspect selectors/targets/object identity or safely identify a development Dock tile.')
        for kind in ('config', 'data', 'state', 'cache'):
            (work / kind).mkdir()
        copied_config = work / 'config/nvim'
        shutil.copytree(config, copied_config, ignore=shutil.ignore_patterns('.git', '__pycache__'))
        (work / 'data/nvim').mkdir()
        (work / 'data/nvim/lazy').symlink_to(plugin_root, target_is_directory=True)
        first, second = work / 'document 用户 text.txt', work / 'second.txt'
        original = 'First user line 用户\nSecond unchanged line\n'
        first.write_text(original)
        second.write_text('Independent second document\n')
        init = work / 'init.lua'
        init.write_text('\n'.join([
            'vim.opt.rtp:prepend(' + json.dumps(str(copied_config), ensure_ascii=False) + ')',
            'vim.opt.rtp:prepend(' + json.dumps(str(plugin_root / 'nvim-treesitter'), ensure_ascii=False) + ')',
            # Keep the real configuration/parser behavior while forbidding installs.
            'local ts=require("nvim-treesitter.configs");local setup=ts.setup',
            'ts.setup=function(opts) opts.ensure_installed={};opts.auto_install=false;return setup(opts) end',
            'vim.g.neovide=true;vim.g.neovide_remember_window_size=false',
            'vim.opt.shortmess:append("I")',
            'dofile(' + json.dumps(str(copied_config / 'init.lua'), ensure_ascii=False) + ')',
        ]))
        (work / 'neovide.toml').write_text('')
        env = os.environ.copy()
        for key in tuple(env):
            if key.startswith('NEOVIDE_') or key in ('NVIM', 'NVIM_LISTEN_ADDRESS', 'NVIM_APPNAME',
                                                    'DYLD_INSERT_LIBRARIES', 'GLOW_MENU_OBSERVER_DIR'):
                env.pop(key)
        for kind in ('CONFIG', 'DATA', 'STATE', 'CACHE'):
            env['XDG_' + kind + '_HOME'] = str(work / kind.lower())
        env.update(NEOVIDE_CONFIG=str(work / 'neovide.toml'), NVIM_SKIP_MATRIX_INTRO='1',
                   TERM='xterm-256color', COLORTERM='truecolor')
        commands = [
            ('nvim', [args.nvim, '--headless', '--listen', str(socket), '-u', str(init),
                      '-i', 'NONE', '-n', str(first)]),
            ('neovide', [str(binary), '--no-fork', '--no-startup-message-capture',
                         '--neovim-bin', args.nvim, '--server', str(socket), '--grid', '120x40']),
        ]
        threading.Thread(target=watchdog, daemon=True).start()
        for name, command in commands:
            if name == 'neovide':
                wait(socket.exists, 'isolated Neovim socket')
            log = (work / (name + '.log')).open('w')
            logs.append(log)
            process_env = env.copy()
            if name == 'neovide' and observer is not None:
                process_env.update(DYLD_INSERT_LIBRARIES=str(observer), GLOW_MENU_OBSERVER_DIR=str(observer_dir))
            process = subprocess.Popen(command, env=process_env, cwd=work, start_new_session=True,
                                       stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT)
            processes.append(process)
            receipt[name + '_pid'] = process.pid
            save()
        if observer is not None:
            wait(lambda: (observer_dir / 'loaded.json').exists(),
                 'DYLD observer did not load; injection may be rejected (see neovide.log)')
            assert json.loads((observer_dir / 'loaded.json').read_text())['pid'] == processes[1].pid
        editor = pynvim.attach('socket', path=str(socket))
        wait(lambda: editor.exec_lua('return vim.g.neovide_native_menu_version==1 and type(neovide)=="table" and type(neovide.set_native_menu_language)=="function"'),
             'real native menu capability')
        assert editor.eval('getpid()') == processes[0].pid, 'connected to an unowned Neovim'
        fixture = editor.exec_lua('''
          local first,second=...
          local firstbuf=vim.fn.bufnr(first)
          local firstwin
          if firstbuf >= 0 then
            for _,win in ipairs(vim.fn.win_findbuf(firstbuf)) do
              if vim.api.nvim_win_get_config(win).relative=='' then firstwin=win;break end
            end
          end
          if not firstwin then
            for _,win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
              if vim.api.nvim_win_get_config(win).relative=='' then firstwin=win;break end
            end
            assert(firstwin,'fixture needs a normal editing window')
            vim.api.nvim_set_current_win(firstwin)
            vim.cmd('edit '..vim.fn.fnameescape(first))
            firstbuf=vim.api.nvim_get_current_buf()
          end
          vim.api.nvim_set_current_win(firstwin)
          vim.cmd('split '..vim.fn.fnameescape(second))
          vim.api.nvim_set_current_win(firstwin)
          vim.api.nvim_buf_set_lines(firstbuf,1,1,false,{'Unsaved user content 保留'})
          vim.api.nvim_win_set_cursor(firstwin,{2,4})
          return {window=firstwin,buffer=firstbuf}
        ''', str(first), str(second))
        # Startup notifications can temporarily own focus. Establish the
        # baseline only after scheduled startup work has stopped moving it.
        stable_since, prior = time.monotonic(), None

        def fixture_settled():
            nonlocal stable_since, prior
            editor.exec_lua('local fixture=...;vim.api.nvim_set_current_win(fixture.window)', fixture)
            snapshot = {'documents': editor.exec_lua(SNAPSHOT), 'geometry': editor.exec_lua(CURSORS)}
            if snapshot != prior:
                stable_since, prior = time.monotonic(), snapshot
                return False
            return time.monotonic() - stable_since >= 2

        wait(fixture_settled, 'document and UI/font geometry stable for two seconds after startup')

        def diagnostic_snapshot(phase):
            start = time.monotonic()
            result = editor.exec_lua(
                'local function cursors()\n' + CURSORS + '\nend\n'
                'local function snapshot()\n' + SNAPSHOT + '\nend\n'
                'local before=cursors();local documents=snapshot();'
                'return {cursors_before=before,documents=documents,cursors_after=cursors()}')
            result['monotonic_start'], result['monotonic_end'] = start, time.monotonic()
            write_json(work / ('phase-' + phase + '.json'), result)
            return result['documents']

        baseline = diagnostic_snapshot('baseline')
        write_json(work / 'documents-before.json', baseline)
        assert any(buffer['modified'] for buffer in baseline['buffers']), 'fixture must contain unsaved edits'
        english_shortcuts, native_windows, registrations, item_semantics = None, None, None, None
        system_baseline = None
        request_sequence = 0
        for index, language in enumerate(('en', 'zh', 'en')):
            phase = f'{index}-{language}'
            diagnostic_snapshot(phase + '-before-set-lang')
            start = time.monotonic()
            immediate = editor.exec_lua(
                'local function cursors()\n' + CURSORS + '\nend\n'
                'local language=...;local before=cursors();'
                'require("config.platform.locale").set_lang(language,{silent=true,save=false});'
                'return {before=before,after=cursors()} ', language)
            immediate['monotonic_start'], immediate['monotonic_end'] = start, time.monotonic()
            write_json(work / ('phase-' + phase + '-set-lang-immediate.json'), immediate)
            diagnostic_snapshot(phase + '-after-set-lang')
            time.sleep(.2)
            diagnostic_snapshot(phase + '-after-sleep')
            observed = {}

            def menus_ready():
                nonlocal observed, request_sequence
                if observer is not None:
                    request_sequence += 1
                    token = f'{index}-{request_sequence}'
                    request = observer_dir / 'request-next.json'
                    write_json(request, {'token': token})
                    request.replace(observer_dir / 'request.json')
                    response = observer_dir / (token + '.json')
                    wait(response.exists, 'AppKit observer snapshot; see observer-error.json/neovide.log')
                    observed = json.loads(response.read_text())
                else:
                    captured = subprocess.run([str(helper), str(processes[1].pid)],
                                              capture_output=True, text=True, timeout=12)
                    assert captured.returncode == 0, captured.stdout + captured.stderr
                    observed = json.loads(captured.stdout)
                write_json(work / f'menus-{index}-{language}.json', observed)
                try:
                    rows = menu_rows(observed, language)
                    if observer is not None:
                        system_window_rows(observed, language)
                    return rows
                except AssertionError:
                    return False

            rows = wait(menus_ready, 'actual native ' + language + ' menu labels')
            shortcuts = {key: {field: value for field, value in node.items() if field.startswith('AXMenuItemCmd')}
                         for key, node in rows.items()}
            if english_shortcuts is None:
                english_shortcuts = shortcuts
            assert shortcuts == english_shortcuts, ('native keyboard equivalents changed', language, shortcuts)
            if observer is not None:
                assert observed.get('observer_phase') == 'after-menu-open-deferred'
                system = system_window_rows(observed, language)
                if system_baseline is None:
                    system_baseline = system
                assert system['device_suffixes'] == system_baseline['device_suffixes'], 'dynamic device names changed'
                for kind in ('known', 'unknown'):
                    for identity in system[kind].keys() & system_baseline[kind].keys():
                        assert system[kind][identity] == system_baseline[kind][identity], (
                            'stable system action semantics or unknown/document title changed', language, kind, identity)
                receipt['checks'][f'{index}-{language}-system'] = {
                    'known_items': len(system['known']), 'fullscreen_items': system['fullscreen_items'],
                    'device_suffixes_unchanged': True, 'stable_actions_and_unknown_titles_unchanged': True}
                semantics = {key: {field: node[field] for field in ('identity', 'selector', 'target')}
                             for key, node in rows.items()}
                if registrations is None:
                    registrations, item_semantics = observed['registrations'], semantics
                    assert all(value != 'nil' for value in registrations.values()), registrations
                assert observed['registrations'] == registrations, 'registered NSMenus were replaced'
                assert semantics == item_semantics, ('native item identity/action/target changed', language)
                if 'dock' in observed:
                    expected_new = '新建窗口' if language == 'zh' else 'New Window'
                    dock = [node for node in descendants(observed['dock']) if node.get('AXTitle') == expected_new]
                    assert dock and dock[0]['selector'] == 'neovideCreateWindow:', ('actual delegate Dock menu', language, observed['dock'])
                    receipt['checks']['dock_delegate'] = True
            if native_windows is None:
                native_windows = observed['windows']
            assert observed['windows'] == native_windows, ('native document windows changed', language)
            snapshot = diagnostic_snapshot(phase + '-after-observer')
            write_json(work / f'documents-{index}-{language}.json', snapshot)
            assert snapshot == baseline, ('language switch changed document/cursor/layout/undo state', language)
            receipt['checks'][f'{index}-{language}'] = {'actual_menu_labels': True, 'shortcuts_unchanged': True,
                                                       'documents_unchanged': True}
            save()
        assert first.read_text() == original, 'unsaved fixture was unexpectedly written to disk'
        assert second.read_text() == 'Independent second document\n'
        if args.visual_hold:
            editor.exec_lua('require("config.platform.locale").set_lang("zh",{silent=true,save=false})')
            receipt['status'] = 'verified_waiting_visual'
            receipt['visual_done_file'] = str(work / 'visual-done')
            save()
            print('Automatic checks passed; owned Chinese UI available for visual inspection: ' + str(work), flush=True)
            deadline = time.monotonic() + args.visual_hold
            while time.monotonic() < deadline and not (work / 'visual-done').exists():
                assert all(process.poll() is None for process in processes), 'owned process exited during visual hold'
                time.sleep(.1)
            receipt['visual_hold_ended_by'] = 'visual-done' if (work / 'visual-done').exists() else 'timeout'
        receipt['status'] = 'passed'
        print('PASS native menus en -> zh -> en; real config, shortcuts and unsaved documents preserved: ' + str(work))
    except BaseException as error:
        if receipt['status'] != 'blocked':
            receipt['status'] = 'failed'
        receipt['error'] = str(error)
        (work / 'failure.log').write_text(traceback.format_exc())
        raise
    finally:
        if editor is not None:
            # Shutdown is bounded by the owned-process watchdog if RPC is wedged.
            try:
                editor.close()
            except Exception:
                pass
        stop_owned()
        done.set()
        receipt['processes_stopped'] = all(process.poll() is not None for process in processes)
        save()
        for log in logs:
            log.close()
        shutil.rmtree(runtime)


if __name__ == '__main__':
    main()
