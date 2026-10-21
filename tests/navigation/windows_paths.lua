-- Real Neovim URI runtime, no plugins, file writes, or language-server launches.
-- GLOW_TEST_CONFIG=/path/to/nvim nvim --headless --noplugin -u NONE -i NONE -l tests/navigation/windows_paths.lua
local config = assert(vim.env.GLOW_TEST_CONFIG, "GLOW_TEST_CONFIG is required")
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
local uri = require("vim.uri")
local native_windows = vim.fn.has("win32") == 1
local original_has, original_get_name = vim.fn.has, vim.api.nvim_buf_get_name
local old_from, old_to = uri.uri_from_fname, uri.uri_to_fname
local public_from, public_to = vim.uri_from_fname, vim.uri_to_fname
local module = require("config.platform.windows_paths")
local buffer

local ok, err = xpcall(function()
    vim.fn.has = function(name)
        if name == "win32" then return 0 end
        return original_has(name)
    end
    module.setup()
    assert(uri.uri_from_fname == old_from and uri.uri_to_fname == old_to, "non-Windows setup must be a no-op")
    assert(vim.uri_from_fname == public_from and vim.uri_to_fname == public_to, "non-Windows public aliases changed")

    local path = [[\\Mac\Home\Desktop\tool.ipynb]]
    local bad = old_from(path)
    assert(bad == "file://%5c%5cMac%5cHome%5cDesktop%5ctool.ipynb", "expected Neovim 0.12.3 UNC regression")
    local baselines = {}
    for _, filename in ipairs({ [[C:\Users\Test\a b.py]], "/tmp/a b.py" }) do
        baselines[filename] = old_from(filename)
    end
    local localhost = old_to("file://localhost/C:/Users/Test/a%20b.py")
    local drive = old_to("file:///C:/Users/Test/a%20b.py")
    vim.fn.has = function(name)
        if name == "win32" then return 1 end
        return original_has(name)
    end
    module.setup()
    local wrapped_from, wrapped_to = uri.uri_from_fname, uri.uri_to_fname
    module.setup()
    assert(uri.uri_from_fname == wrapped_from and uri.uri_to_fname == wrapped_to, "setup stacked wrappers")
    assert(vim.uri_from_fname == wrapped_from and vim.uri_to_fname == wrapped_to, "public aliases must use repaired functions")
    assert(vim.uri_from_fname(path) == "file://Mac/Home/Desktop/tool.ipynb")
    assert(vim.uri_from_fname("//Mac/Home/Desktop/tool.ipynb") == "file://Mac/Home/Desktop/tool.ipynb")
    for _, filename in ipairs({ path, [[\\Mac\Home\Desktop\空 格#100%.py]] }) do
        local value = vim.uri_from_fname(filename)
        assert(vim.uri_to_fname(value) == filename, "UNC URI roundtrip failed: " .. value)
    end
    local encoded = vim.uri_from_fname([[\\Mac\Home\Desktop\空 格#100%.py]])
    assert(encoded:find("%20", 1, true) and encoded:find("%23", 1, true) and encoded:find("%25", 1, true))
    assert(vim.uri_to_fname("file://Mac/Home/Desktop/tool.ipynb#location") == path, "URI fragments must not become filenames")
    for filename, baseline in pairs(baselines) do
        assert(vim.uri_from_fname(filename) == baseline, "non-UNC encoding changed")
    end
    assert(vim.uri_to_fname("file://localhost/C:/Users/Test/a%20b.py") == localhost, "localhost behavior changed")
    assert(vim.uri_to_fname("file:///C:/Users/Test/a%20b.py") == drive, "drive decoding changed")
    assert(vim.uri_to_fname("untitled:test") == "untitled:test", "custom schemes changed")

    buffer = vim.api.nvim_create_buf(false, true)
    if native_windows then
        vim.api.nvim_buf_set_name(buffer, path)
    else
        -- A Mac cannot give a buffer a native Windows UNC filename. Model only
        -- that API boundary while exercising the real runtime buffer URI code.
        vim.api.nvim_buf_get_name = function(bufnr)
            if bufnr == buffer then return path end
            return original_get_name(bufnr)
        end
    end
    assert(vim.uri_from_bufnr(buffer) == "file://Mac/Home/Desktop/tool.ipynb", "buffer URI bypassed repair")
    assert(uri.uri_from_bufnr(buffer) == "file://Mac/Home/Desktop/tool.ipynb", "runtime module bypassed repair")
    print("PASS Windows UNC URI compatibility (" .. (native_windows and "native buffer" or "Mac with modeled Windows buffer name") .. ")")
end, debug.traceback)

vim.fn.has, vim.api.nvim_buf_get_name = original_has, original_get_name
if buffer and vim.api.nvim_buf_is_valid(buffer) then
    vim.api.nvim_buf_delete(buffer, { force = true })
end
if not ok then error(err) end
