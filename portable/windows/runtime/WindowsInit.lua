-- Loaded before lazy by the installed profile only. Application files remain
-- read-only; kernels, remote-plugin registration and caches live in the profile.
if vim.fn.has("win32") ~= 1 then return end
local root = assert(vim.env.NEOVIDE_GLOW_ROOT, "Neovide Glow installation root is missing")
root = vim.fs.normalize(root):gsub("/$", "")
if vim.g.neovide_glow_windows_runtime == root then return end

local runtime = require("config.media.runtime")
local python = vim.env.GLOW_PYTHON or vim.env.NEOVIDE_GLOW_PYTHON or root .. "/runtime/python/python.exe"
python = vim.fs.normalize(python)
local jupytext = root .. "/bin/jupytext.exe"
assert(vim.fn.executable(python) == 1, "The packaged Python runtime is missing: " .. python)
assert(vim.fn.executable(jupytext) == 1, "The packaged Jupytext launcher is missing: " .. jupytext)

function runtime.python() return python end
function runtime.jupytext() return jupytext end
function runtime.ready()
  return vim.fn.executable(python) == 1 and vim.fn.executable(jupytext) == 1
end
function runtime.prepare_host()
  -- An explicit --cmd/user host selection remains authoritative.
  if not vim.g.python3_host_prog or vim.g.python3_host_prog == "" then vim.g.python3_host_prog = python end
end
runtime.prepare_host()
vim.env.GLOW_PYTHON, vim.env.NEOVIDE_GLOW_PYTHON = python, python
vim.env.GLOW_LATEX2TEXT = root .. "/bin/latex2text.exe"

-- Molten's frozen client writes connection files under data_dir/runtime even
-- when JUPYTER_RUNTIME_DIR points elsewhere. Prepare only this private profile.
local function prepare_jupyter_directory(declared, home, suffix)
  if not declared or declared == "" then return end
  assert(home and home ~= "", "The packaged Jupyter profile home is missing")
  local directory = vim.fs.normalize(declared, { expand_env = false }):gsub("/$", "")
  local expected = vim.fs.normalize(home .. "/jupyter", { expand_env = false }):gsub("/$", "")
  assert(directory:lower() == expected:lower(), "Jupyter directory is outside the packaged profile")
  directory = directory .. suffix
  vim.fn.mkdir(directory, "p", 448)
  assert(vim.fn.isdirectory(directory) == 1, "Cannot prepare the packaged Jupyter directory: " .. directory)
end
prepare_jupyter_directory(vim.env.JUPYTER_DATA_DIR, vim.env.XDG_DATA_HOME, "/runtime")
prepare_jupyter_directory(vim.env.JUPYTER_RUNTIME_DIR, vim.env.XDG_STATE_HOME, "")

local uv = vim.uv or vim.loop
local share = runtime.directory() .. "/share/jupyter"
local kernel = share .. "/kernels/" .. runtime.default_kernel .. "/kernel.json"
vim.fn.mkdir(vim.fs.dirname(kernel), "p")
local specification = {
  argv = { python, "-Xfrozen_modules=off", "-m", "ipykernel_launcher", "-f", "{connection_file}" },
  display_name = "Neovide Glow Python", language = "python", metadata = { debugger = true },
}
local encoded = vim.json.encode(specification)
local current = vim.fn.filereadable(kernel) == 1 and table.concat(vim.fn.readfile(kernel), "\n") or ""
if current ~= encoded then
  local staging = kernel .. ".preparing-" .. vim.fn.getpid() .. "-" .. uv.hrtime()
  assert(vim.fn.writefile({ encoded }, staging) == 0, "Cannot prepare the packaged Python kernel")
  local renamed, err = uv.fs_rename(staging, kernel)
  if not renamed then vim.fn.delete(staging); error("Cannot register the packaged Python kernel: " .. tostring(err)) end
end
-- The immutable Python distribution need not contain user-profile kernels.
local paths, found = {}, false
for _, path in ipairs(vim.split(vim.env.JUPYTER_PATH or "", ";", { plain = true, trimempty = true })) do
  if vim.fs.normalize(path):lower() == vim.fs.normalize(share):lower() then found = true end
  paths[#paths + 1] = path
end
if not found then table.insert(paths, 1, share) end
vim.env.JUPYTER_PATH = table.concat(paths, ";")

local manifest = vim.fs.normalize(vim.fn.stdpath("data") .. "/rplugin.vim")
-- Prevent an inherited manifest override from directing writes outside this
-- launcher's private profile. This changes only the current child process.
vim.env.NVIM_RPLUGIN_MANIFEST = manifest
local group = vim.api.nvim_create_augroup("GlowWindowsPackagedRuntime", { clear = true })
vim.api.nvim_create_autocmd("VimEnter", {
  group = group, once = true,
  callback = function()
    if vim.fn.filereadable(manifest) == 1 then return end
    local molten = vim.fn.stdpath("data") .. "/lazy/molten-nvim"
    if vim.fn.filereadable(molten .. "/rplugin/python3/molten/__init__.py") ~= 1 then
      vim.notify("Packaged Notebook plugin is missing; reinstall Neovide Glow.", vim.log.levels.ERROR)
      return
    end
    vim.schedule(function()
      if vim.fn.filereadable(manifest) == 1 then return end
      local ok, err = pcall(function()
        -- Lazy has now added the bundled plugin to runtimepath. Registration
        -- inspects Python plugin declarations and never issues MoltenInit.
        if vim.fn.exists(":UpdateRemotePlugins") ~= 2 then vim.cmd("runtime plugin/rplugin.vim") end
        assert(type(vim.g.loaded_remote_plugins) == "string"
          and vim.fs.normalize(vim.g.loaded_remote_plugins):lower() == manifest:lower(),
          "Remote-plugin manifest is outside the packaged profile")
        vim.cmd("UpdateRemotePlugins")
        assert(vim.fn.filereadable(manifest) == 1, "Remote-plugin registration did not produce a manifest")
        local lines = vim.fn.readfile(manifest)
        -- Nvim's manifest generator interpolates paths into single-quoted
        -- Vimscript. Escape profile names such as O'Connor before sourcing it.
        for index, line in ipairs(lines) do
          local path = line:match("^call remote#host#RegisterPlugin%('python3', '(.*)', %[$")
          if path then lines[index] = "call remote#host#RegisterPlugin('python3', '" .. path:gsub("'", "''") .. "', [" end
        end
        local contents = table.concat(lines, "\n")
        assert(contents:find("MoltenInit", 1, true), "The packaged Molten plugin could not be registered")
        assert(vim.fn.writefile(lines, manifest) == 0, "Cannot save the profile's remote-plugin manifest")
        vim.cmd("source " .. vim.fn.fnameescape(manifest))
      end)
      if not ok then
        -- A failed/empty generated manifest must not prevent a later retry.
        if vim.fn.filereadable(manifest) == 1 then vim.fn.delete(manifest) end
        vim.notify("Notebook registration failed: " .. tostring(err), vim.log.levels.ERROR)
      end
    end)
  end,
})
vim.g.neovide_glow_windows_runtime = root
