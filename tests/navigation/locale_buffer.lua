-- Actual GUI buffer-local mappings, including LSP and Treesitter jumps.
-- Uses WhichKey's global=false expansion/filter, without invoking mapped actions.
local config = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = { config, vim.env.VIMRUNTIME, vim.fn.expand("~/.local/share/nvim/lazy/which-key.nvim") }
local snapshot = vim.json.decode(table.concat(vim.fn.readfile(assert(vim.env.GLOW_LOCALE_BUFFER_SNAPSHOT)), "\n"))
local stdpath, lang, lc = vim.fn.stdpath, vim.env.LANG, vim.env.LC_ALL
local work = vim.fn.tempname()
vim.fn.stdpath = function(name)
  return name == "state" and work or name == "config" and (work .. "/config") or stdpath(name)
end
vim.g.mapleader = " "
local ok, err = xpcall(function()
  assert(#snapshot.maps == 103, "expected the complete real Lua buffer capture")
  local locale = require("config.platform.locale")
  local actions = 0
  for _, map in ipairs(snapshot.maps) do
    if not map.desc:find("which-key-trigger", 1, true) then
      actions = actions + 1
      vim.keymap.set(map.mode, map.lhs, function() end, { buffer = true, desc = map.desc })
    end
  end
  local spec = dofile(config .. "/lua/plugins/editor/which_key.lua")
  require("which-key").setup(spec.opts(nil, {}))
  vim.api.nvim_exec_autocmds("VimEnter", {})
  assert(vim.wait(500, function() return require("which-key.config").loaded end))
  local view = require("which-key.view")
  local function sample(language)
    locale.set_lang(language, { save = false, silent = true })
    local rows = {}
    for _, mode in ipairs({ "n", "x", "i", "o" }) do
      local registered = require("which-key.buf").get({ mode = mode, update = true })
      for _, child in ipairs(registered.tree.root:children()) do
        local items = view.expand(registered.tree.root, child, function() return true end,
          function(node) return not node.hidden and node:is_local() end)
        for _, item in ipairs(items) do
          rows[#rows + 1] = { mode = mode, keys = item.node.keys, desc = item.desc, icon = item.icon }
          if language == "zh" then
            assert(locale.known(item.node.desc), "buffer-local label was missed: " .. tostring(item.node.desc))
            assert(item.desc ~= item.node.desc, "English remained in buffer menu: " .. item.node.desc)
          end
        end
      end
    end
    table.sort(rows, function(a, b) return a.mode .. a.keys < b.mode .. b.keys end)
    return rows
  end
  local en, zh, restored = sample("en"), sample("zh"), sample("en")
  assert(vim.deep_equal(en, restored), "buffer menu did not restore after en/zh/en")
  assert(#en == actions, "WhichKey did not display every captured local action")
  for i, item in ipairs(en) do
    assert(item.mode == zh[i].mode and item.keys == zh[i].keys and item.icon == zh[i].icon, "key or icon changed")
  end
  locale.set_lang("zh", { save = false, silent = true })
  assert(locale.t("Goto Definition") == "跳转到定义")
  assert(locale.t("Signature Help") == "查看函数签名")
  assert(locale.t("Goto previous start @parameter.inner") == "跳转到上一个参数的起点")
  assert(locale.t("Goto next end @function.outer") == "跳转到下一个函数的终点")
  if vim.env.GLOW_LOCALE_BUFFER_OUTPUT then
    vim.fn.writefile({ vim.json.encode({ captured = #snapshot.maps, actions = actions, en = en, zh = zh, restored = restored }) },
      vim.env.GLOW_LOCALE_BUFFER_OUTPUT)
  end
  print(("PASS actual GUI buffer scope: %d captured mappings, %d visible actions; LSP, references, Git hunks, 12 textobject jumps, actual WhichKey global=false en/zh/en"):format(#snapshot.maps, actions))
end, debug.traceback)
vim.fn.stdpath, vim.env.LANG, vim.env.LC_ALL = stdpath, lang, lc
vim.fn.delete(work, "rf")
if not ok then error(err) end
