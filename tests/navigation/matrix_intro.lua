-- Isolated UI startup fixture: use --embed (without --headless), then attach a UI.
-- GLOW_TEST_CONFIG selects a configuration root; GLOW_INTRO_CASE selects a branch.
local api = vim.api
local config = assert(vim.env.GLOW_TEST_CONFIG, "GLOW_TEST_CONFIG is required")
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
vim.g.neovide = vim.env.GLOW_INTRO_CASE ~= "nongui"
vim.g.neovide_normal_opacity = 0.78
local case = vim.env.GLOW_INTRO_CASE or "normal"
if case == "skip" then
  vim.env.NVIM_SKIP_MATRIX_INTRO = "1"
end
local executable = vim.fn.executable
if case == "missing" then
  vim.fn.executable = function(name)
    return name == "cmatrix-gm" and 0 or executable(name)
  end
end
if case == "jobfail" then
  vim.fn.jobstart = function()
    return -1
  end
end
local original_win = api.nvim_get_current_win()
require("config.appearance.intro")
vim.fn.executable = executable
local cover
for _, win in ipairs(api.nvim_list_wins()) do
  if api.nvim_win_get_config(win).zindex == 250 then
    cover = win
  end
end
local expected = case == "normal" or case == "jobfail"
assert((cover ~= nil) == expected, "cover must exist before VimEnter only when enabled")
assert(api.nvim_get_current_win() == original_win, "cover stole the startup window")
if cover then
  local namespace = api.nvim_get_namespaces().GlowMatrixIntro
  assert(namespace and api.nvim_get_hl_ns({ winid = cover }) == namespace)
  assert(api.nvim_win_get_config(cover).focusable == false)
  api.nvim_set_hl(0, "Normal", { fg = "#ffffff", bg = "#ff0000" })
  vim.cmd("colorscheme default")
  local dashboard_buf = api.nvim_create_buf(false, true)
  vim.bo[dashboard_buf].filetype = "snacks_dashboard_terminal"
  local dashboard = api.nvim_open_win(dashboard_buf, false, {
    relative = "editor", row = 3, col = 3, width = 30, height = 6, style = "minimal",
  })
  vim.wo[dashboard].winhighlight = "Normal:SnacksDashboardTerminal"
  for _, rgb in ipairs({ 0x123456, 0xf0e8da, 0x123456 }) do
    api.nvim_set_hl(0, "Normal", { fg = 0xabcdef, bg = rgb })
    api.nvim_set_hl(0, "SnacksDashboardTerminal", { bg = rgb, blend = 80 })
    api.nvim_exec_autocmds("ColorScheme", { modeline = false })
    require("config.appearance.transparency").apply()
    local dashboard_hl = api.nvim_get_hl(0, { name = "SnacksDashboardTerminal", link = false })
    assert(dashboard_hl.bg == rgb and dashboard_hl.blend == 22, "Dashboard override differs from editor")
    for _, win in ipairs({ cover, dashboard }) do
      local state = vim.w[win].glow_popup_material
      assert(state.mode == "editor", "Matrix did not receive the editor material")
      local attrs = api.nvim_get_hl(api.nvim_get_hl_ns({ winid = win }), { name = "Normal" })
      assert(attrs.bg == rgb and attrs.blend == 22, "Matrix RGB/absolute alpha differs from editor")
    end
    assert(vim.w[cover].glow_popup_material.profile == "matrix_intro")
    assert(vim.w[dashboard].glow_popup_material.profile == "matrix_dashboard")
  end
  api.nvim_win_close(dashboard, true)
  api.nvim_buf_delete(dashboard_buf, { force = true })
  vim.cmd.redraw()
end
local cover_buf = cover and api.nvim_win_get_buf(cover)
api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    assert(api.nvim_get_current_win() == original_win, "terminal stole the dashboard window")
    if case == "normal" then
      assert(api.nvim_win_is_valid(cover), "cover disappeared before terminal startup")
      assert(vim.bo[cover_buf].buftype == "terminal", "VimEnter did not start Matrix directly")
    elseif case == "jobfail" then
      assert(not api.nvim_win_is_valid(cover), "failed job left a blocking cover")
    end
    vim.g.glow_intro_probe = { case = case, early_cover = expected, passed = true }
    if cover then
      vim.defer_fn(function()
        assert(not api.nvim_win_is_valid(cover), "intro window leaked after timeout")
        assert(not api.nvim_buf_is_valid(cover_buf), "intro buffer leaked after timeout")
        vim.g.glow_intro_cleanup = true
      end, 2200)
    end
  end,
})
