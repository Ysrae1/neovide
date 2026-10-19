-- No kernels: exercise actual runtime setup and both theme refresh hooks.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
vim.opt.rtp:prepend(vim.env.GLOW_TEST_CONFIG or (root .. "/portable/payload/nvim"))
package.preload["config.media.molten_images"] = function()
  return { setup = function() return false end }
end
vim.api.nvim_set_hl(0, "Normal", { fg = 0xe6e6e6, bg = 0x171717 })
vim.api.nvim_set_hl(0, "Comment", { fg = 0x666666, italic = true })
vim.api.nvim_set_hl(0, "MoltenVirtualText", { link = "Comment" })
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "print(42)", "raise ValueError('example')" })
local namespace = vim.api.nvim_create_namespace("molten-extmarks")
for index, lines in ipairs({ { "Out[1]: ✓ Done", "42" }, { "Out[2]: ✗ Failed", "ValueError: example" } }) do
  local chunks = {}
  for _, line in ipairs(lines) do chunks[#chunks + 1] = { { line, "MoltenVirtualText" } } end
  vim.api.nvim_buf_set_extmark(buf, namespace, index - 1, 0, { virt_lines = chunks })
end
local marks = vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })
local source = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
local changedtick = vim.api.nvim_buf_get_changedtick(buf)
local function normal_output()
  return vim.deep_equal(vim.api.nvim_get_hl(0, { name = "MoltenVirtualText", link = false }),
    vim.api.nvim_get_hl(0, { name = "Normal", link = false }))
end
local runtime = require("config.media.runtime")
runtime.configure_molten()
assert(normal_output(), "Out/status/body inherit normal foreground without Comment styling")
assert(vim.api.nvim_get_hl(0, { name = "MoltenVirtualText", link = true }).link == "Normal")
local semantic = {}
for _, name in ipairs({ "Number", "Success", "Failure", "Error", "Running" }) do
  local hl = vim.api.nvim_get_hl(0, { name = "GlowNotebookOutput" .. name, link = false })
  assert(hl.fg and not hl.bg and not hl.italic, "semantic groups keep normal brightness and no background")
  semantic[name] = hl.fg
end
assert(semantic.Success ~= semantic.Failure and semantic.Number ~= semantic.Failure)
assert(semantic.Error == semantic.Failure)
runtime.configure_molten()
assert(#vim.api.nvim_get_autocmds({ group = "GlowNotebookOutputHighlights" }) == 2, "setup stays idempotent")
vim.api.nvim_set_hl(0, "Normal", { fg = 0x222222, bg = 0xfafafa })
vim.api.nvim_set_hl(0, "MoltenVirtualText", { link = "Comment" })
vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "output-light" })
assert(vim.wait(1000, normal_output, 10), "ColorScheme restores normal output")
vim.api.nvim_set_hl(0, "Normal", { fg = 0xf0f0f0, bg = 0x202020 })
vim.api.nvim_set_hl(0, "MoltenVirtualText", { link = "Comment" })
vim.api.nvim_exec_autocmds("User", { pattern = "NvThemeReload" })
assert(vim.wait(1000, normal_output, 10), "NvThemeReload restores normal output")
assert(vim.deep_equal(marks, vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })), "output marks unchanged")
assert(vim.deep_equal(source, vim.api.nvim_buf_get_lines(buf, 0, -1, false)) and changedtick == vim.api.nvim_buf_get_changedtick(buf), "source unchanged")
assert(vim.fn.exists(":MoltenInit") == 0 and not vim.g.loaded_python3_provider, "no Python host or kernel loaded")
print(vim.json.encode({ normal_output = true, semantic_groups = true, theme_hooks = 2, output_marks_unchanged = true, kernels_started = 0 }))
