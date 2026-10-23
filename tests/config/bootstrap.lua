-- Startup wiring contract: execute the real entry points with isolated feature
-- providers, without loading plugins, opening a GUI or touching user settings.
local config = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
local original_has = vim.fn.has
local receipt = { state = "started", config = config, cases = {} }
local native = {
  ["config.bootstrap"] = "lua/config/bootstrap.lua",
  ["config.platform.neovide"] = "lua/config/platform/neovide.lua",
  ["config.media"] = "lua/config/media/init.lua",
}
local providers = {
  "config.platform.windows_appearance", "config.platform.macos_appearance",
  "config.platform.glass", "config.appearance.transparency",
  "config.appearance.render_roles", "config.appearance.float_shadows",
  "config.platform.neovide_zoom", "config.media.image", "config.media.preview",
  "config.media.notebook", "config.media.notebook_edit", "config.media.book",
  "config.media.open", "config.appearance.intro", "config.appearance.startup",
  "config.lazy", "config.platform.locale", "config.platform.macos_keymaps",
  "config.editor.settings",
}
local media = { "image", "preview", "notebook", "notebook_edit", "book", "open" }
local load_scale, save_scale = function() end, function() end
local draft = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(draft, 0, -1, false, { "unsaved startup fixture" })
local changedtick = vim.api.nvim_buf_get_changedtick(draft)

local ok, err = xpcall(function()
  for _, case in ipairs({
    { name = "Mac GUI", gui = true, platform = "mac" },
    { name = "Windows GUI", gui = true, platform = "windows" },
    { name = "Linux GUI", gui = true, platform = "linux" },
    { name = "terminal", gui = false, platform = "mac" },
  }) do
    local trace, options = {}, {}
    local function record(value) trace[#trace + 1] = value end
    vim.g.neovide = case.gui
    vim.fn.has = function(name)
      if name == "win32" then return case.platform == "windows" and 1 or 0 end
      if name == "macunix" then return case.platform == "mac" and 1 or 0 end
      return original_has(name)
    end
    for name, path in pairs(native) do
      local module, source = name, path
      package.loaded[module] = nil
      package.preload[module] = function()
        record(module)
        return assert(loadfile(config .. "/" .. source))()
      end
    end
    for _, name in ipairs(providers) do
      local module = name
      package.loaded[module] = nil
      package.preload[module] = function()
        record(module)
        return {
          setup = function(opts)
            record(module .. ".setup")
            options[module] = opts
          end,
          load_scale_factor = load_scale,
          save_scale_factor = save_scale,
        }
      end
    end

    assert(loadfile(config .. "/init.lua"))()
    local expected = { "config.bootstrap", "config.platform.neovide" }
    local function provider(name)
      expected[#expected + 1] = name
      expected[#expected + 1] = name .. ".setup"
    end
    if case.gui then
      provider(case.platform == "windows" and "config.platform.windows_appearance" or "config.platform.macos_appearance")
      provider("config.platform.glass")
      provider("config.appearance.transparency")
      provider("config.appearance.render_roles")
      provider("config.appearance.float_shadows")
      provider("config.platform.neovide_zoom")
      expected[#expected + 1] = "config.media"
      for _, name in ipairs(media) do provider("config.media." .. name) end
      assert(vim.deep_equal(options["config.appearance.float_shadows"], {
        notebook_output = case.platform == "mac", matrix_intro = case.platform == "mac",
      }), "platform shadow policy changed")
      if case.platform == "windows" then
        assert(options["config.platform.windows_appearance"].initialize == true, "Windows defaults initialized too late")
      end
      local gui = package.loaded["config.platform.neovide"]
      assert(gui.load_scale_factor == load_scale and gui.save_scale_factor == save_scale, "zoom compatibility exports changed")
    else
      assert(package.loaded["config.media"] == nil, "terminal initialized native media")
    end
    vim.list_extend(expected, { "config.appearance.intro", "config.appearance.startup", "config.lazy" })
    provider("config.platform.locale")
    vim.list_extend(expected, { "config.platform.macos_keymaps", "config.editor.settings" })
    assert(vim.deep_equal(trace, expected), case.name .. " startup order changed:\n" .. vim.inspect(trace))

    -- Re-entering the init file retains require caching. Only locale.setup()
    -- ran again in the original entry point; native setup must not repeat.
    trace = {}
    assert(loadfile(config .. "/init.lua"))()
    assert(vim.deep_equal(trace, { "config.platform.locale.setup" }), "repeated init duplicated native setup")
    assert(vim.api.nvim_get_current_buf() == draft and vim.bo[draft].modified, "startup wiring changed the draft")
    assert(vim.api.nvim_buf_get_changedtick(draft) == changedtick, "startup wiring edited the draft")
    receipt.cases[#receipt.cases + 1] = case.name .. ": original order, cached re-entry and draft preserved"
  end
  receipt.state = "passed"
end, debug.traceback)
vim.fn.has = original_has
if not ok then receipt.state = "failed"; receipt.error = err end
if vim.env.GLOW_TEST_RECEIPT then
  vim.fn.writefile({ vim.json.encode(receipt) }, vim.env.GLOW_TEST_RECEIPT)
end
assert(ok, err)
print("PASS bootstrap: original GUI/terminal order, native media registration and cached re-entry")
vim.cmd("qa!")
