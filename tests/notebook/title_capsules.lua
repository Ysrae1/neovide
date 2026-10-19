-- No kernels: evaluate the real winbar syntax, widths, palette and theme refresh.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
vim.opt.rtp:prepend(vim.env.GLOW_TEST_CONFIG or (root .. "/portable/payload/nvim"))
vim.g.mapleader = " "
vim.o.background = "dark"
package.preload.base46 = function()
  return { get_theme_tb = function(kind)
    assert(kind == 'base_16' or kind == 'base_30')
    return { base0D = vim.o.background == 'dark' and '#96D7F3' or '#55B4D4',
      base0B = vim.o.background == 'dark' and '#C5F760' or '#86B300',
      vibrant_green = vim.o.background == 'dark' and '#B5F297' or '#94E76B' }
  end }
end
vim.api.nvim_set_hl(0, "Normal", { fg = 0xffffff, bg = 0x171717 })
vim.api.nvim_set_hl(0, "St_file_txt", { fg = 0xcccccc, bg = 0x252934 })
for name, color in pairs({ St_NormalMode = 0x5599cc, St_VisualMode = 0x55bb99, St_InsertMode = 0xaa77cc }) do
  vim.api.nvim_set_hl(0, name, { fg = 0x171717, bg = color })
end
local notebook = require("config.media.notebook_edit")
notebook.setup()
local function rendered(session, width, layout)
  return vim.api.nvim_eval_statusline(notebook.render_title(session, width, layout), {
    winid = vim.api.nvim_get_current_win(), use_winbar = true, maxwidth = width, highlights = true,
  })
end
local idle = rendered({}, 80)
assert(idle.str:find("KERNEL   ␣jk", 1, true) and idle.str:find("CELLS  ↑ [c   ↓ ]c", 1, true) and idle.str:find("MENU  ␣j", 1, true))
local _, left_ends = idle.str:gsub("", "")
local _, right_ends = idle.str:gsub("", "")
assert(left_ends == 3 and right_ends == 3)
for _, label in ipairs({ 'KERNEL', 'CELLS', 'MENU' }) do
  assert(idle.str:find('' .. label, 1, true), 'left cap touches label ' .. label)
  assert(not idle.str:find(' ' .. label, 1, true), 'no extra leading label space ' .. label)
end
assert(not idle.str:find(' ', 1, true), 'right cap touches value')
assert(not idle.str:find("空格", 1, true))
assert(not idle.str:find("/", 1, true) and not idle.str:find("Kernel:", 1, true))
local long = rendered({ ready = true, selected = { display_name = string.rep("Long Kernel ", 30) } }, 64)
assert(long.width == 64 and long.str:find("…", 1, true))
assert(long.str:find("↑ [c   ↓ ]c", 1, true) and long.str:find("MENU  ␣j", 1, true))
assert(not long.str:find('<', 1, true), 'width budget must not invoke statusline truncation')
local exact = rendered({ ready = true, kernel = '123456789012345678901' }, 64)
assert(exact.width == 64 and exact.str:find('123456789012345678901', 1, true), 'actual capsule width budget')
assert(not long.str:find(' ', 1, true), 'long title right cap touches value')
vim.g.neovide_native_notebook=true;vim.g.neovide_native_notebook_viewport=true
local native = rendered({ready=true,kernel='glow-python'},98,{textoff=8,host_width=100})
assert(native.width==98 and native.str:match('^ *')==string.rep(' ',7),'Kernel starts at nearest input-border cell')
assert(native.str:sub(-#'')=='','Menu ends at actual text-grid boundary, beyond language capsule inset')
assert(math.abs(7-(8-.8))<=.5,'left alignment rounds to nearest whole winbar cell')
assert(math.abs(98-(100-1.12))<1,'reserved native viewport limits right alignment to under one cell')
local native_full = rendered({ready=true,kernel='glow-python'},100,{textoff=4,host_width=100})
assert(native_full.str:match('^ *')==string.rep(' ',3) and native_full.str:sub(-1)==' ', 'unresized viewport frame insets')
local native_long = rendered({ready=true,kernel=string.rep('Long ',40)},62,{textoff=8,host_width=64})
assert(native_long.width==62 and native_long.str:find('…',1,true) and not native_long.str:find('<',1,true), 'aligned title retains right groups without statusline truncation')
vim.g.neovide_native_notebook=nil;vim.g.neovide_native_notebook_viewport=nil
local narrow = rendered({ ready = true, kernel = string.rep("name", 30) }, 40)
assert(narrow.width == 40 and narrow.str:find("[c  ]c", 1, true) and narrow.str:find("M  ␣j", 1, true))
assert(not narrow.str:find(' ', 1, true), 'narrow right cap touches value')
assert(rendered({ready=true,kernel='glow-python   '},100).str:find('glow-python',1,true), 'trim external value whitespace')
assert(rendered({ starting = true, requested = "glow-python" }, 100).str:find("KERNEL  ◌ glow-python", 1, true))
assert(rendered({ ready = true, kernel = "glow-python" }, 100).str:find("KERNEL  glow-python", 1, true))
assert(rendered({ selected = { display_name = "Base" } }, 100).str:find("KERNEL  ■ Base", 1, true))
local function contrast(color, background)
  local function linear(channel)
    channel = channel / 255
    return channel <= 0.04045 and channel / 12.92 or ((channel + 0.055) / 1.055) ^ 2.4
  end
  local function luminance(value)
    local red, green, blue = math.floor(value / 65536), math.floor(value / 256) % 256, value % 256
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  end
  local a, b = luminance(color), luminance(background)
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05)
end
local colors = {}
for _, name in ipairs({ "Kernel", "Cells", "Menu" }) do
  local body = vim.api.nvim_get_hl(0, { name = "GlowNotebook" .. name, link = false })
  local cap = vim.api.nvim_get_hl(0, { name = "GlowNotebook" .. name .. "Cap", link = false })
  local value = vim.api.nvim_get_hl(0, { name = "GlowNotebook" .. name .. "Value", link = false })
  local value_cap = vim.api.nvim_get_hl(0, { name = "GlowNotebook" .. name .. "ValueCap", link = false })
  assert(body.fg == 0x171717 and body.bg and cap.fg == body.bg and not cap.bg)
  assert(value.bg == 0x252934 and value.fg == body.bg and value_cap.fg == value.bg and not value_cap.bg)
  assert(contrast(value.fg, value.bg) >= 4.5)
  assert(not colors[body.bg]); colors[body.bg] = true
end
assert(not vim.api.nvim_get_hl(0, { name = "GlowNotebookBar", link = false }).bg)
local previous = vim.api.nvim_get_hl(0, { name = "GlowNotebookPrev", link = false })
local following = vim.api.nvim_get_hl(0, { name = "GlowNotebookNext", link = false })
local cells_value = vim.api.nvim_get_hl(0, { name = "GlowNotebookCellsValue", link = false })
assert(previous.fg == following.fg and previous.fg == cells_value.fg and previous.bg == 0x252934 and following.bg == 0x252934)
assert(previous.fg == 0xc5f760 and vim.api.nvim_get_hl(0,{name='GlowNotebookCells',link=false}).bg == 0xc5f760)
local function output_capsule_matches_border()
  local function hl(suffix) return vim.api.nvim_get_hl(0, { name = 'GlowNotebookExpand' .. suffix, link = false }) end
  assert(hl('').bg == notebook.output_accent() and hl('Cap').fg == notebook.output_accent()
    and hl('Value').fg == notebook.output_accent(), 'output capsule and border share the exact theme RGB')
end
output_capsule_matches_border()
vim.g.mapleader = ","
assert(rendered({}, 80).str:find(" ,jk", 1, true))
vim.g.mapleader = "<Space>"
assert(notebook.leader_label() == "␣")
local old_color = vim.api.nvim_get_hl(0, { name = "GlowNotebookKernel", link = false }).bg
vim.api.nvim_set_hl(0, "St_NormalMode", { fg = 0x222222, bg = 0x88bbdd })
vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "capsule-test" })
assert(vim.wait(1000, function()
  return vim.api.nvim_get_hl(0, { name = "GlowNotebookKernel", link = false }).bg ~= old_color
end, 10))
-- Attach a text-only fixture without reading a notebook or starting any host.
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '.ipynb')
local source = { '# %% [markdown]', '# Heading', '', '# %%', 'print(42)', '', '# %%', '', '# %%', 'only_line' }
vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
vim.bo[buf].filetype = 'python'
vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = buf })
local labels = notebook.cell_labels(buf)
assert(#labels == 4 and labels[1].row == 1 and labels[2].row == 4 and labels[3].row == 7 and labels[4].row == 9)
local function joined(chunks)
  local text='';for _,chunk in ipairs(chunks) do text=text..chunk[1] end;return text
end
assert(joined(labels[1].chunks):find('',1,true) and not joined(labels[1].chunks):find('Markdown',1,true))
assert(joined(labels[2].chunks):find('',1,true) and not joined(labels[2].chunks):find('python',1,true))
local code_text=joined(labels[2].chunks)
assert(code_text:find('󰼛',1,true) < code_text:find('',1,true), 'run precedes right-aligned type')
assert(code_text:find('󰘶󰌑',1,true) and not code_text:find('[()]'), 'shortcut has no parentheses')
for _, kind in ipairs({'markdown','raw','code'}) do
  local text=joined(notebook.label_chunks(kind,'python',false))
  assert(not text:find(' ',1,true),'no space after left semicircle '..kind)
  assert(not text:find(' ',1,true),'no space before right semicircle '..kind)
end
assert(labels[2].chunks[#labels[2].chunks-1][2]=='GlowNotebookLanguage', 'type remains the last capsule')
assert(labels[2].width==vim.fn.strdisplaywidth(joined(labels[2].chunks)) and labels[2].accent==notebook.cell_accent())
local cell_accent=vim.api.nvim_get_hl(0,{name='GlowNotebookCell',link=false}).bg
assert(cell_accent==0x96d7f3)
assert(notebook.output_accent()==0xb5f297)
for _,name in ipairs({'Markdown','Language','Raw','Run'}) do
  local body=vim.api.nvim_get_hl(0,{name='GlowNotebook'..name,link=false})
  local cap=vim.api.nvim_get_hl(0,{name='GlowNotebook'..name..'Cap',link=false})
  assert(body.bg==cell_accent and body.fg==0x222222 and cap.fg==cell_accent and not cap.bg)
end
local run_value=vim.api.nvim_get_hl(0,{name='GlowNotebookRunValue',link=false})
assert(run_value.fg==cell_accent and run_value.bg==0x252934)
local _, caps = joined(labels[2].chunks):gsub('','');assert(caps==2)
local idle_label, running_label = notebook.label_chunks('code','python',false), notebook.label_chunks('code','python',true)
for index,chunk in ipairs(idle_label) do
  if chunk[1]:find('󰼛',1,true) then assert(running_label[index][1]==chunk[1]:gsub('󰼛','󰐊'))
  else assert(vim.deep_equal(chunk,running_label[index])) end
end
local ns=vim.api.nvim_get_namespaces()['glow.notebook.cells']
for _,mark in ipairs(vim.api.nvim_buf_get_extmarks(buf,ns,0,-1,{details=true})) do
  assert(mark[4].virt_text_pos=='eol_right_align' and not mark[4].line_hl_group)
end
vim.api.nvim_win_set_cursor(0,{2,0});notebook.jump(1);assert(vim.api.nvim_win_get_cursor(0)[1]==5)
notebook.jump(1);assert(vim.api.nvim_win_get_cursor(0)[1]==8)
notebook.jump(1);assert(vim.api.nvim_win_get_cursor(0)[1]==10)
notebook.jump(-1);assert(vim.api.nvim_win_get_cursor(0)[1]==8)
assert(vim.deep_equal(source,vim.api.nvim_buf_get_lines(buf,0,-1,false)))
vim.g.neovide_native_notebook=true
local ui=package.loaded['config.media.notebook_ui']
local saved_owner,saved_border_owner=ui.text_borders,ui.border_labels;ui.text_borders=false;ui.border_labels=true
assert(#notebook.refresh_labels(buf)==4 and #vim.api.nvim_buf_get_extmarks(buf,ns,0,-1,{})==0)
ui.text_borders=false;ui.border_labels=false
notebook.refresh_labels(buf)
assert(#vim.api.nvim_buf_get_extmarks(buf,ns,0,-1,{})==4)
ui.text_borders=saved_owner;ui.border_labels=saved_border_owner
vim.o.background='light'
notebook.refresh_title_colors()
output_capsule_matches_border()
vim.api.nvim_set_hl(0,'St_NormalMode',{fg=0xfafafa,bg=0x399ee6})
notebook.refresh_title_colors()
assert(vim.api.nvim_get_hl(0,{name='GlowNotebookKernelValue',link=false}).bg==0xffffff)
assert(notebook.cell_accent()==0x55b4d4 and vim.api.nvim_get_hl(0,{name='GlowNotebookRunValue',link=false}).bg==0xffffff)
assert(notebook.output_accent()==0x94e76b)
assert(vim.api.nvim_get_hl(0,{name='GlowNotebookCells',link=false}).bg == 0x86b300)
assert(vim.api.nvim_get_hl(0,{name='GlowNotebookKernel',link=false}).fg == 0xfafafa)
assert(vim.api.nvim_get_hl(0,{name='GlowNotebookLanguage',link=false}).fg == 0xfafafa)
print(vim.json.encode({ segmented_capsules=3, surface='dark/light adaptive', previous_next='same Cells accent',
  label_capsules='run before right-aligned type; no parentheses', cell_accent='theme base0D', running='only triangle changes', anchor='visible content/empty row',
  native_ui='explicit border ownership / native source fallback', source='unchanged', kernels_started=0 }))
