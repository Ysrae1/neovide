-- Versioned declarations keep theme names out of the native renderer. These
-- defaults preserve older Glow configurations; a configuration can replace the
-- entire map, including declaring renamed or third-party groups.
local defaults = {}
local function assign(names, role)
    for _, name in ipairs(names) do defaults[name] = { role } end
end
assign({ "GlowNotebookLanguage", "GlowNotebookMarkdown" }, "enlarged_icon")
assign({ "AvanteReversedTitle", "AvanteReversedSubtitle", "AvanteReversedThirdTitle" }, "solid_title_cap")
for _, suffix in ipairs({ "", "Cap", "Value", "ValueCap" }) do
    defaults["GlowNotebookKernel" .. suffix] = { "notebook_kernel" }
    defaults["GlowNotebookCells" .. suffix] = { "notebook_actions" }
    defaults["GlowNotebookMenu" .. suffix] = { "notebook_actions" }
end
assign({ "GlowNotebookPrev", "GlowNotebookNext" }, "notebook_actions")

local function publish(groups)
    if groups == nil then groups = vim.g.neovide_highlight_roles end
    if groups == nil then groups = defaults end
    if type(groups) == "table" and next(groups) == nil then groups = vim.empty_dict() end
    vim.rpcnotify(vim.g.neovide_channel_id, "neovide.highlight_roles", { version = 1, groups = groups })
end

_G.neovide.set_highlight_roles = function(groups)
    vim.g.neovide_highlight_roles = groups
    publish(groups)
end
vim.g.neovide_highlight_roles_version = 1
local group = vim.api.nvim_create_augroup("neovide_highlight_roles", { clear = true })
vim.api.nvim_create_autocmd({ "VimEnter", "ColorScheme" }, {
    group = group, callback = function() publish() end,
})
publish()
