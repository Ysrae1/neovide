"""Real TeX + SyncTeX, actual VimTeX output lookup, asynchronous Neovim bridge.
Run with the Notebook venv Python (pynvim). Compiles only its isolated fixture.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import time
import pynvim

ROOT = Path(__file__).resolve().parents[2]
TEXBIN = Path('/Library/TeX/texbin')
VIMTEX = Path.home() / '.local/share/nvim/lazy/vimtex'

with tempfile.TemporaryDirectory(prefix="glow synctex's ") as directory:
    fixture = Path(directory)
    (fixture / 'build').mkdir()
    main = fixture / 'main document.tex'
    source = fixture / 'chapter with spaces.tex'
    main.write_text('\\documentclass{article}\n\\begin{document}\n'
                    '\\input{chapter with spaces.tex}\n\\newpage\nSecond page.\n\\end{document}\n')
    source.write_text('First paragraph.\n\nThe exact synchronization target is this sentence.\n\nLast paragraph.\n')
    subprocess.run([str(TEXBIN / 'pdflatex'), '-interaction=nonstopmode', '-halt-on-error',
                    '-synctex=1', '-output-directory=build', main.name], cwd=fixture,
                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True)
    pdf = fixture / 'build/main document.pdf'
    nvim = pynvim.attach('child', argv=['nvim', '--embed', '-u', 'NONE', '-n'])
    try:
        nvim.ui_attach(110, 40, rgb=True)
        nvim.exec_lua("vim.opt.rtp:prepend(...)", str(VIMTEX))
        nvim.exec_lua("vim.opt.rtp:prepend(...)", str(ROOT / 'portable/payload/nvim'))
        nvim.exec_lua("""
          vim.g.vimtex_compiler_latexmk={out_dir='build'}
          vim.g.vimtex_view_method='skim_async'
          vim.g.neovide_native_preview=true;vim.g.neovide_channel_id=77
          _G.calls={}; _G.notices={}
          vim.rpcnotify=function(_,method,...) calls[#calls+1]={method,...};return true end
          vim.notify=function(text) notices[#notices+1]=text end
          require('config.media.preview').setup()
        """)
        nvim.command('filetype plugin on')
        nvim.command('cd ' + nvim.funcs.fnameescape(str(fixture)))
        nvim.command('edit ' + nvim.funcs.fnameescape(str(main)))
        nvim.command('edit ' + nvim.funcs.fnameescape(str(source)))
        nvim.current.window.cursor = (3, 7)
        source_win = nvim.current.window.handle
        actual = nvim.eval("b:vimtex.compiler.get_file('pdf')")
        assert Path(actual).resolve() == pdf.resolve(), actual

        def wait_for(expression):
            for _ in range(150):
                result = nvim.exec_lua('return ' + expression)
                if result:
                    return result
                time.sleep(.02)
            raise AssertionError((expression, nvim.exec_lua('return notices')))

        nvim.command('GlowTexForward')
        point = wait_for("(function() for _,c in ipairs(calls) do if c[1]=='neovide.preview.pdf_sync' then return c[3] end end end)()")
        assert point['page'] == 1 and point['width'] > 0 and point['height'] > 0, point
        assert nvim.current.window.handle == source_win, 'forward preserves source focus'
        assert any(c[0] == 'neovide.preview.open' and Path(c[3]).resolve() == pdf.resolve()
                   for c in nvim.exec_lua('return calls')), nvim.exec_lua('return calls')
        nvim.current.window.cursor = (1, 0)
        assert nvim.exec_lua("local pdf,point,win=...;return require('config.media.synctex').inverse(pdf,point,{win=win})",
                             str(pdf), point, source_win)
        wait_for('vim.api.nvim_win_get_cursor(0)[1]==3')
        assert Path(nvim.current.buffer.name).resolve() == source.resolve()
        nvim.exec_lua('calls={}')
        nvim.command('VimtexView')
        wait_for("(function() for _,c in ipairs(calls) do if c[1]=='neovide.preview.pdf_sync' then return true end end end)()")
        assert not nvim.eval('b:vimtex.compiler.is_running()'), 'view must never compile'
        nvim.exec_lua('calls={}')
        nvim.command('GlowTexForward ' + nvim.funcs.fnameescape(str(pdf)))
        wait_for("(function() for _,c in ipairs(calls) do if c[1]=='neovide.preview.pdf_sync' then return true end end end)()")
        nvim.exec_lua("vim.g.glow_tex_viewer='skim'")
        assert nvim.exec_lua("return require('config.media.synctex').native_enabled()") is False
        nvim.exec_lua("vim.g.glow_tex_viewer=nil;calls={}")
        missing = fixture / 'missing mapping.pdf'
        shutil.copyfile(pdf, missing)
        assert nvim.exec_lua("return require('config.media.synctex').forward(...)", str(missing)) is False
        assert not nvim.exec_lua('return calls')
        assert 'synctex' in nvim.exec_lua('return notices[#notices]')
        print('PASS: real SyncTeX forward/inverse; included TeX + VimTeX out_dir; spaces/apostrophe paths; VimtexView; source focus; no compilation; missing mapping; Skim opt-out')
    finally:
        try:
            nvim.command('qa!')
        except Exception:
            pass
