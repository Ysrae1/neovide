-- Real frozen Neo-tree modules; no plugin installation or GUI session.
-- GLOW_TEST_CONFIG=/path/to/nvim GLOW_NEO_TREE_PLUGIN=/path/to/neo-tree.nvim
-- GLOW_NEO_TREE_DEPS=/path/to/plenary.nvim;/path/to/nui.nvim
-- nvim --headless --noplugin -u NONE -i NONE -l tests/navigation/neo_tree_unc.lua
-- On Windows, GLOW_UNC_FIXTURE_ROOT may select an existing UNC directory.
-- Without that variable this models Windows fs_lstat only; it is not Windows QA.
local config = assert(vim.env.GLOW_TEST_CONFIG, "GLOW_TEST_CONFIG is required")
local plugin = assert(vim.env.GLOW_NEO_TREE_PLUGIN, "GLOW_NEO_TREE_PLUGIN is required")
vim.opt.rtp = { config, plugin, vim.env.VIMRUNTIME }
for _, dependency in ipairs(vim.split(vim.env.GLOW_NEO_TREE_DEPS or "", ";", { trimempty = true })) do
    vim.opt.rtp:append(dependency)
end

local uv = vim.uv or vim.loop
local utils = require("neo-tree.utils")
local items = require("neo-tree.sources.common.file-items")
local log = require("neo-tree.log")
local real_windows = vim.fn.has("win32") == 1
local original = {
    has = vim.fn.has,
    fs_lstat = uv.fs_lstat,
    log_error = log.error,
    windows = utils.is_windows,
    separator = utils.path_separator,
}

local ok, err = xpcall(function()
    local fixture = vim.env.GLOW_UNC_FIXTURE_ROOT
    local share, child
    if fixture then
        assert(real_windows, "a real UNC fixture requires native Windows Neovim")
        fixture = fixture:gsub("/", "\\"):gsub("\\+$", "")
        share = assert(fixture:match([[^(\\[^\]+\[^\]+)]]), "fixture must be a UNC directory")
        child = fixture
        local stat = original.fs_lstat(fixture)
        assert(stat and stat.type == "directory", "UNC fixture must already exist; this test writes nothing")
    else
        share, child = [[\\GlowFixture\Share]], [[\\GlowFixture\Share\child]]
        uv.fs_lstat = function(path, ...)
            local canonical = path:gsub("\\+$", "")
            if canonical == share or canonical == child then
                return { type = "directory" }
            end
            if path:sub(1, 2) == [[\\]] then
                return nil, "ENOENT: fixture server-only path is not a directory"
            end
            return original.fs_lstat(path, ...)
        end
    end
    utils.is_windows, utils.path_separator = true, "\\"
    vim.fn.has = function(name)
        if name == "win32" then
            return 1
        end
        return original.has(name)
    end

    local failures = {}
    log.error = function(...)
        local parts = {}
        for index = 1, select("#", ...) do
            parts[index] = tostring(select(index, ...))
        end
        failures[#failures + 1] = table.concat(parts)
    end
    local broken_parent = utils.split_path(share)
    assert(broken_parent and broken_parent ~= share, "expected the frozen UNC parent regression before patch")
    local before = items.create_context({ path = child })
    local before_ok, before_error = pcall(items.create_item, before, child, "directory")
    assert(not before_ok, "unpatched real create_item must reproduce the parent failure")
    assert(table.concat(failures, "\n"):find("insert", 1, true)
        or tostring(before_error):find("insert", 1, true), "expected the original nil-children insert failure")

    local drive_parent, drive_name = utils.split_path([[C:\Users\Example]])
    local drive_root_parent, drive_root_name = utils.split_path([[C:\]])
    local navigation = require("config.navigation.neo_tree")
    assert(type(navigation.setup_paths) == "function", "setup_paths must be available")
    navigation.setup_paths()
    local wrapped = utils.abspath_prefix
    navigation.setup_paths()
    assert(utils.abspath_prefix == wrapped, "repeated setup must not stack wrappers")

    local parent, name = utils.split_path(share)
    assert(parent == nil and name == share, "UNC share must be a root without a parent")
    local child_parent = utils.split_path(share .. [[\child]])
    assert(child_parent == share or child_parent == share .. [[\]], "child parent must remain the UNC share")
    local after_drive_parent, after_drive_name = utils.split_path([[C:\Users\Example]])
    local after_root_parent, after_root_name = utils.split_path([[C:\]])
    assert(after_drive_parent == drive_parent and after_drive_name == drive_name, "drive directory behavior changed")
    assert(after_root_parent == drive_root_parent and after_root_name == drive_root_name, "drive root behavior changed")
    utils.is_windows, utils.path_separator = false, "/"
    assert(utils.abspath_prefix("/tmp/example") == "/", "POSIX root behavior changed")
    utils.is_windows, utils.path_separator = true, "\\"

    failures = {}
    local after = items.create_context({ path = child })
    local item = items.create_item(after, child, "directory")
    assert(item.path == child and item.type == "directory", "real create_item must succeed after repair")
    local share_item = after.folders[share] or after.folders[share .. [[\]]]
    assert(share_item and type(share_item.children) == "table", "share directory children missing")
    assert(#failures == 0, "patched create_item still reported parent failures: " .. table.concat(failures, "\n"))
    print("PASS neo-tree UNC roots: frozen failure reproduced; repaired paths, parents, idempotency checked ("
        .. (fixture and "native Windows existing UNC fixture" or "simulated Windows filesystem; no native Windows QA") .. ")")
end, debug.traceback)

vim.fn.has, uv.fs_lstat, log.error = original.has, original.fs_lstat, original.log_error
utils.is_windows, utils.path_separator = original.windows, original.separator
if not ok then
    error(err)
end
