-- A composed picker casts one outer shadow. Window-local role mappings retain
-- their identity even when linked theme highlights collapse to NormalFloat.
local api = vim.api
local previous, queued
local child = {
    SnacksPickerInput = true, SnacksPickerInputBorder = true,
    SnacksPickerList = true, SnacksPickerListBorder = true,
    SnacksPickerPreview = true, SnacksPickerPreviewBorder = true,
}
local function roles(win)
    local is_child, is_box = false, false
    for _, mapping in ipairs(vim.split(vim.wo[win].winhighlight, ",", { plain = true })) do
        local name = mapping:match("^[^:]+:(.+)$")
        is_child = is_child or child[name] == true
        is_box = is_box or name == "SnacksPickerBox" or name == "SnacksPickerBoxBorder"
    end
    return is_child, is_box
end
local function publish(windows, redraw)
    if vim.deep_equal(previous, windows) then return end
    previous = windows
    vim.rpcnotify(vim.g.neovide_channel_id, "neovide.window.shadow_exclusions", windows)
    if redraw then vim.cmd.redraw() end
end
local function refresh()
    queued = false
    local windows, configs, children, boxes = {}, {}, {}, {}
    for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
        local config = api.nvim_win_get_config(win)
        if config.relative ~= "" then
            configs[win] = config
            children[win], boxes[win] = roles(win)
        end
    end
    for win, config in pairs(configs) do
        local nested_box = boxes[win] and config.relative == "win" and boxes[config.win]
        if children[win] or nested_box then windows[#windows + 1] = win end
    end
    table.sort(windows)
    publish(windows, true)
end
local function schedule()
    if queued then return end
    queued = true
    vim.schedule(refresh)
end
local group = api.nvim_create_augroup("neovide_composed_float_shadow", { clear = true })
api.nvim_create_autocmd({ "WinNew", "WinClosed", "WinEnter", "BufWinEnter", "TabEnter" }, {
    group = group, callback = schedule,
})
api.nvim_create_autocmd("OptionSet", { group = group, pattern = "winhighlight", callback = schedule })
api.nvim_create_autocmd("TabLeave", { group = group, callback = function() publish({}, false) end })
schedule()
