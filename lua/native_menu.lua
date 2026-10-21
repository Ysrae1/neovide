-- The host menu belongs to AppKit; UI text is changed without recreating it.
_G.neovide = _G.neovide or {}
_G.neovide.set_native_menu_language = function(language)
    assert(language == "en" or language == "zh", "Native menu language must be en or zh")
    vim.rpcnotify(vim.g.neovide_channel_id, "neovide.native_menu.language", {
        version = 1,
        language = language,
    })
end
vim.g.neovide_native_menu_version = 1
vim.api.nvim_exec_autocmds("User", { pattern = "NeovideNativeMenuReady", modeline = false })
