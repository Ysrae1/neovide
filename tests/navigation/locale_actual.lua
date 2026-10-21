-- Verify descriptions captured from the running GUI, using the real WhichKey renderer.
-- The two JSON snapshots are read-only QA inputs, never executed as key actions.
local config = assert(vim.env.GLOW_TEST_CONFIG)
local maps_file = assert(vim.env.GLOW_LOCALE_MAP_SNAPSHOT)
local tree_file = assert(vim.env.GLOW_LOCALE_TREE_SNAPSHOT)
vim.opt.rtp = { config, vim.env.VIMRUNTIME, vim.fn.expand("~/.local/share/nvim/lazy/which-key.nvim") }
local stdpath, lang, lc = vim.fn.stdpath, vim.env.LANG, vim.env.LC_ALL
local work = vim.fn.tempname()
vim.fn.stdpath = function(name)
  return name == "state" and work or name == "config" and (work .. "/config") or stdpath(name)
end
local ok, err = xpcall(function()
  local function read(path) return vim.json.decode(table.concat(vim.fn.readfile(path), "\n")) end
  local snapshot, captured = read(maps_file), read(tree_file)
  assert(#snapshot.maps == 212 and #captured >= 266, "expected the actual expanded GUI capture, including window proxies")
  vim.g.mapleader = snapshot.leader
  local locale = require("config.platform.locale")
  local opts = { spec = {} }
  local seen = {}
  for _, map in ipairs(snapshot.maps) do
    if map.desc ~= "which-key-trigger" then
      vim.keymap.set(map.mode, map.lhs, function() end, { desc = map.desc })
      seen[map.mode .. map.lhs] = true
    end
  end
  -- Keep every captured group and descriptionless action, not just LazyVim defaults.
  local dynamic = {}
  for _, node in ipairs(captured) do
    if node.dynamic then dynamic[node.mode .. node.keys] = true end
    if node.desc and node.group then
      local spec = { node.keys, mode = node.mode, group = node.desc, proxy = node.proxy }
      local entries = {}
      for _, child in ipairs(captured) do
        local suffix = child.keys:sub(#node.keys + 1)
        if child.mode == node.mode and child.dynamic and child.keys:sub(1, #node.keys) == node.keys and suffix:match("^%d$") then
          entries[#entries + 1] = { suffix, function() end, desc = child.desc, icon = { cat = "file", name = child.desc } }
        end
      end
      if #entries > 0 then spec.expand = function() return vim.deepcopy(entries) end end
      opts.spec[#opts.spec + 1] = spec
    elseif not node.group and not node.dynamic then
      local key = node.source_keys or node.keys
      if not seen[node.mode .. key] then
        vim.keymap.set(node.mode, key, function() end, { desc = node.desc or node.rendered })
      end
    end
  end
  locale.setup()
  opts = dofile(config .. "/lua/plugins/editor/which_key.lua").opts(nil, opts)
  require("which-key").setup(opts)
  vim.api.nvim_exec_autocmds("VimEnter", {})
  assert(vim.wait(500, function() return require("which-key.config").loaded end))
  local view = require("which-key.view")
  local rows, missing = {}, {}
  local function sample(language)
    locale.set_lang(language, { save = false, silent = true })
    local output = {}
    for _, mode in ipairs({ "n", "x" }) do
      local registered = require("which-key.buf").get({ mode = mode, update = true })
      local root = assert(registered.tree:find(vim.g.mapleader))
      local function visit(node, route, depth)
        assert(depth < 12, "unexpected proxy loop")
        if node.hidden then return end
        local item = view.item(node, { parent = node.parent })
        output[#output + 1] = { mode = mode, keys = route, desc = item.desc, group = not not item.group, icon = item.icon }
        if language == "zh" and node.desc and not dynamic[mode .. route] and not locale.known(node.desc) then
          missing[#missing + 1] = node.desc
        end
        for _, child in ipairs(node:children()) do visit(child, route .. child.key, depth + 1) end
      end
      visit(root, root.keys, 0)
    end
    table.sort(output, function(a, b) return a.mode .. a.keys < b.mode .. b.keys end)
    return output
  end
  rows.en, rows.zh, rows.en_again = sample("en"), sample("zh"), sample("en")
  if vim.env.GLOW_LOCALE_OUTPUT then
    vim.fn.writefile({ vim.json.encode({ tree = rows }) }, vim.env.GLOW_LOCALE_OUTPUT)
  end
  assert(vim.deep_equal(rows.en, rows.en_again), "the entire WhichKey tree did not restore after en/zh/en")
  local routes = {}
  for _, row in ipairs(rows.zh) do routes[row.mode .. row.keys] = true end
  local absent = {}
  for _, row in ipairs(captured) do
    if not routes[row.mode .. row.keys] then absent[#absent + 1] = row.mode .. row.keys end
  end
  assert(#absent == 0, "captured menu branches disappeared: " .. vim.inspect(absent))
  for i, row in ipairs(rows.en) do
    for _, field in ipairs({ "mode", "keys", "group", "icon" }) do
      assert(vim.deep_equal(row[field], rows.zh[i][field]), "language changed " .. field .. " for " .. row.keys)
    end
    if dynamic[row.mode .. row.keys] then
      assert(row.desc == rows.zh[i].desc, "a user file/window title was translated")
    end
  end
  assert(#missing == 0, "unknown real tree descriptions: " .. vim.inspect(missing))
  locale.set_lang("zh", { save = false, silent = true })
  local checked = 0
  for _, map in ipairs(snapshot.maps) do
    if map.desc ~= "which-key-trigger" then
      assert(locale.known(map.desc), "untranslated GUI action: " .. map.desc)
      local text = view.replace("desc", map.desc)
      assert(not text:find("缓冲区", 1, true), "user requires preserving buffer: " .. map.desc)
      assert(text ~= map.desc or map.desc == "LazyGit", "English action remained: " .. map.desc)
      checked = checked + 1
    end
  end
  local expected = {
    ["Explorer NeoTree (Root Dir)"] = "NeoTree 文件浏览（根目录）",
    ["Explorer NeoTree (cwd)"] = "NeoTree 文件浏览（当前目录）",
    ["Notification History"] = "通知历史",
    ["Buffer Keymaps (which-key)"] = "当前 buffer 的快捷键",
    ["Keywordprg"] = "查看光标词帮助",
    ["Keymaps"] = "快捷键",
    ["UI"] = "UI 设置",
    ["code"] = "代码功能",
  }
  for original, chinese in pairs(expected) do assert(view.replace("desc", original) == chinese, original) end
  for _, mapping in ipairs(require("which-key.plugins.presets").windows) do
    if mapping.desc then assert(locale.known(mapping.desc), "window preset was not translated: " .. mapping.desc) end
  end
  assert(view.replace("desc", "Window Hydra Mode (which-key)") == "连续执行窗口操作（WhichKey）")
  assert(view.replace("desc", "windows") == "窗口功能")
  assert(locale.t("  󰒲  FIND   CONFIG FILE  ") == "  󰒲  查找配置文件  ")
  assert(locale.t("+noice") == "+消息管理（Noice）")
  assert(locale.t("My custom user label") == "My custom user label")
  assert(locale.t("C:/Users/Find Config File.py") == "C:/Users/Find Config File.py")
  if vim.env.GLOW_LOCALE_OUTPUT then
    vim.fn.writefile({ vim.json.encode({ actions_checked = checked, captured_actions = #snapshot.maps, tree = rows }) }, vim.env.GLOW_LOCALE_OUTPUT)
  end
  print(("PASS actual GUI: %d/212 actions (2 hidden triggers), %d real tree rows, en/zh/en; labels, icons, keys and unknown user text preserved"):format(checked, #rows.zh))
end, debug.traceback)
vim.fn.stdpath, vim.env.LANG, vim.env.LC_ALL = stdpath, lang, lc
vim.fn.delete(work, "rf")
if not ok then error(err) end
