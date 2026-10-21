-- Early bootstrap for an explicitly migrated, user-owned configuration.
-- Call from the former profile's init.lua BEFORE WindowsInit.lua or any require:
-- return dofile(helper_path).load(target_path, { legacy_config = old_config })
-- This helper never copies, overwrites, deletes, or creates configuration files.
local M = {}
local state_key = "neovide_glow.config_redirect_state"

local function normalize(path)
  assert(type(path) == "string" and path ~= "", "Glow configuration path is missing")
  local absolute = path:match("^%a:[/\\]") or path:match("^[/\\][/\\]") or path:sub(1, 1) == "/"
  assert(absolute, "Glow configuration path must be absolute: " .. path)
  return vim.fs.normalize(path, { expand_env = false }):gsub("/+$", "")
end

local function identity(path)
  local value = vim.fs.normalize(path, { expand_env = false }):gsub("/+$", "")
  return vim.fn.has("win32") == 1 and value:lower() or value
end

-- vim.opt:get() splits escaped commas too. Preserve valid user-directory names
-- with the same backslash-comma escaping as Neovim's path option parser.
local function path_list(raw)
  local paths, current, i = {}, {}, 1
  while i <= #raw do
    local ch = raw:sub(i, i)
    if ch == "\\" and raw:sub(i + 1, i + 1) == "," then
      current[#current + 1], i = ",", i + 2
    elseif ch == "," then
      paths[#paths + 1], current, i = table.concat(current), {}, i + 1
    else
      current[#current + 1], i = ch, i + 1
    end
  end
  paths[#paths + 1] = table.concat(current)
  return paths
end

local function replace_paths(raw, old, target)
  local result, found_root, found_after = {}, false, false
  local old_id, target_id = identity(old), identity(target)
  for _, path in ipairs(path_list(raw)) do
    local id = identity(path)
    if id == old_id or id == target_id then
      if not found_root then result[#result + 1], found_root = target, true end
    elseif id == old_id .. "/after" or id == target_id .. "/after" then
      if not found_after then result[#result + 1], found_after = target .. "/after", true end
    else
      result[#result + 1] = path
    end
  end
  if not found_root then table.insert(result, 1, target) end
  if not found_after then result[#result + 1] = target .. "/after" end
  for i, path in ipairs(result) do result[i] = path:gsub(",", "\\,") end
  return table.concat(result, ",")
end

local function validate(target, opts)
  opts = opts or {}
  target = normalize(target)
  local old = normalize(opts.legacy_config or vim.env.NEOVIDE_GLOW_LEGACY_CONFIG or vim.fn.stdpath("config"))
  local appname = vim.env.NVIM_APPNAME
  assert(not appname or appname == "" or appname == "nvim", "Glow config redirect requires NVIM_APPNAME=nvim")
  assert(vim.fs.basename(target) == "nvim", "Glow configuration directory must be named nvim")
  assert(vim.fn.isdirectory(target) == 1, "Glow configuration directory does not exist: " .. target)
  local init = target .. "/init.lua"
  assert(vim.fn.filereadable(init) == 1, "Glow configuration init.lua is missing: " .. init)
  local chunk, load_error = loadfile(init)
  assert(chunk, "Cannot load Glow configuration: " .. tostring(load_error))
  return target, old, init, chunk
end

-- Restore only the paths changed by activate(). No module or user-buffer reload.
function M.restore(previous)
  vim.env.XDG_CONFIG_HOME = previous.config_home
  vim.env.NEOVIDE_GLOW_LEGACY_CONFIG = previous.legacy
  vim.env.MYVIMRC = previous.myvimrc
  vim.o.runtimepath, vim.o.packpath = previous.runtimepath, previous.packpath
end

local function activate(target, old, init)
  local previous = {
    config_home = vim.env.XDG_CONFIG_HOME,
    legacy = vim.env.NEOVIDE_GLOW_LEGACY_CONFIG,
    myvimrc = vim.env.MYVIMRC,
    runtimepath = vim.o.runtimepath,
    packpath = vim.o.packpath,
  }
  local ok, err = xpcall(function()
    vim.env.XDG_CONFIG_HOME = vim.fs.dirname(target)
    vim.env.NEOVIDE_GLOW_LEGACY_CONFIG = old
    vim.o.runtimepath = replace_paths(previous.runtimepath, old, target)
    vim.o.packpath = replace_paths(previous.packpath, old, target)
    vim.env.MYVIMRC = init
    assert(identity(vim.fn.stdpath("config")) == identity(target), "Neovim did not select the migrated configuration")
  end, debug.traceback)
  if not ok then
    M.restore(previous)
    error(err, 0)
  end
  return previous
end

-- Safe hot entry: validates/compiles init.lua but NEVER executes it. Existing
-- modules, buffers, plugins and WindowsInit remain in place. Repeating this
-- operation is idempotent. Keep the returned snapshot for M.restore(snapshot).
function M.activate(target, opts)
  local resolved, old, init = validate(target, opts)
  return activate(resolved, old, init)
end

function M.load(target, opts)
  local resolved, old, init, chunk = validate(target, opts)
  local state = package.loaded[state_key]
  assert(not state or not state.active, "Recursive Glow configuration redirect detected")
  if state and state.loaded_target == identity(resolved) then return state.value end
  assert(identity(resolved) ~= identity(old), "Glow configuration redirect points to its own source")
  state = state or {}
  package.loaded[state_key] = state
  local previous = activate(resolved, old, init)
  state.active = true
  local ok, value = xpcall(chunk, debug.traceback)
  state.active = false
  if not ok then
    M.restore(previous)
    -- Arbitrary init.lua side effects cannot be rolled back. Do not silently
    -- load another configuration into a partly initialized process.
    error("Glow configuration redirect failed; restore the former init.lua and restart.\n" .. value, 0)
  end
  state.loaded_target, state.value = identity(resolved), value
  return value
end

return M
