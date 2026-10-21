#!/usr/bin/env python3
"""Real macOS native-menu en -> zh -> en regression, using only owned processes.

Run with the existing Notebook Python (pynvim); an existing installation is also
auto-detected. Requires Xcode command-line tools and existing Accessibility
authorization for the launching host. No authorization prompt is requested.

  python3 tests/macos/native_menu_language.py \
    --binary /absolute/development/Neovide.app/Contents/MacOS/neovide \
    --config ~/.config/nvim --output /absolute/QA/native-menu-local-1

The actual config is copied, existing plugins are reused, and state/data/cache
are isolated. Plugin installation and updates are disabled. Only temporary text
fixtures are edited. Logs, menu snapshots, document snapshots and receipt.json
are retained. This test does not install a build or inspect other editors.
Dock menus are not tested: a bare development binary has no safely identifiable
Dock tile when another Neovide instance is running. No debug RPC is introduced.
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--nvim', default=shutil.which('nvim'))
    parser.add_argument('--plugin-root', type=Path, default=Path.home() / '.local/share/nvim/lazy')
    parser.add_argument('--timeout', type=float, default=25)
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
    pynvim = pynvim_module()
    work = args.output.expanduser().resolve()
    work.mkdir(parents=True, exist_ok=False)
    # Short socket paths avoid the macOS sockaddr_un limit even for long QA paths.
    runtime = Path(tempfile.mkdtemp(prefix='glow-native-menu-'))
    socket = runtime / 'nvim.sock'
    receipt = {'status': 'starting', 'binary': str(binary), 'config': str(config),
               'output': str(work), 'socket': str(socket), 'checks': {},
               'limitations': ['Dock menu not checked; no unambiguous owned Dock tile is assumed.',
                               'AX exposes shortcut metadata, not Objective-C selectors or targets.']}
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
        if not done.wait(120):
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
        if trusted.returncode != 0:
            receipt['status'] = 'blocked'
            raise RuntimeError('Existing Accessibility authorization is unavailable; no GUI was started and no prompt requested')
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
            if key.startswith('NEOVIDE_') or key in ('NVIM', 'NVIM_LISTEN_ADDRESS', 'NVIM_APPNAME'):
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
            process = subprocess.Popen(command, env=env, cwd=work, start_new_session=True,
                                       stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT)
            processes.append(process)
            receipt[name + '_pid'] = process.pid
            save()
        editor = pynvim.attach('socket', path=str(socket))
        wait(lambda: editor.exec_lua('return vim.g.neovide_native_menu_version==1 and type(neovide)=="table" and type(neovide.set_native_menu_language)=="function"'),
             'real native menu capability')
        assert editor.eval('getpid()') == processes[0].pid, 'connected to an unowned Neovim'
        editor.exec_lua('''
          local second=...
          vim.cmd('split '..vim.fn.fnameescape(second));vim.cmd('wincmd p')
          vim.api.nvim_buf_set_lines(0,1,1,false,{'Unsaved user content 保留'})
          vim.api.nvim_win_set_cursor(0,{2,4})
        ''', str(second))
        time.sleep(.2)
        baseline = editor.exec_lua(SNAPSHOT)
        write_json(work / 'documents-before.json', baseline)
        assert any(buffer['modified'] for buffer in baseline['buffers']), 'fixture must contain unsaved edits'
        english_shortcuts, native_windows = None, None
        for index, language in enumerate(('en', 'zh', 'en')):
            editor.exec_lua('require("config.platform.locale").set_lang(...,{silent=true,save=false})', language)
            time.sleep(.2)
            observed = {}

            def menus_ready():
                nonlocal observed
                captured = subprocess.run([str(helper), str(processes[1].pid)],
                                          capture_output=True, text=True, timeout=12)
                assert captured.returncode == 0, captured.stdout + captured.stderr
                observed = json.loads(captured.stdout)
                write_json(work / f'menus-{index}-{language}.json', observed)
                try:
                    return menu_rows(observed, language)
                except AssertionError:
                    return False

            rows = wait(menus_ready, 'actual native ' + language + ' menu labels')
            shortcuts = {key: {field: value for field, value in node.items() if field.startswith('AXMenuItemCmd')}
                         for key, node in rows.items()}
            if english_shortcuts is None:
                english_shortcuts = shortcuts
            assert shortcuts == english_shortcuts, ('native keyboard equivalents changed', language, shortcuts)
            if native_windows is None:
                native_windows = observed['windows']
            assert observed['windows'] == native_windows, ('native document windows changed', language)
            snapshot = editor.exec_lua(SNAPSHOT)
            write_json(work / f'documents-{index}-{language}.json', snapshot)
            assert snapshot == baseline, ('language switch changed document/cursor/layout/undo state', language)
            receipt['checks'][f'{index}-{language}'] = {'actual_menu_labels': True, 'shortcuts_unchanged': True,
                                                       'documents_unchanged': True}
            save()
        assert first.read_text() == original, 'unsaved fixture was unexpectedly written to disk'
        assert second.read_text() == 'Independent second document\n'
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
