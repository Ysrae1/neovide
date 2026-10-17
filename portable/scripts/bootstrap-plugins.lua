-- Run with the isolated profile's XDG_* variables and -u NONE.
-- NEOVIDE_BUNDLE_PAYLOAD=/path/to/payload NVIM_BUNDLE_PHASE=parsers|mason|health
local payload = assert(vim.env.NEOVIDE_BUNDLE_PAYLOAD, "NEOVIDE_BUNDLE_PAYLOAD is required")
local phase = vim.env.NVIM_BUNDLE_PHASE or "health"
local data = vim.fn.stdpath("data")
local function read_json(path)
  return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
end
local function ensure(condition, message)
  if not condition then error(message) end
end
local function read_text(path)
  return table.concat(vim.fn.readfile(path, "b"), "\n")
end
local plugin_manifest = read_json(payload .. "/plugins.json")
for _, plugin in ipairs(plugin_manifest.plugins) do
  local path = data .. "/lazy/" .. plugin.name
  ensure(vim.fn.isdirectory(path) == 1, "Missing pinned plugin: " .. path)
  vim.opt.runtimepath:append(path)
end
vim.opt.runtimepath:prepend(vim.fn.stdpath("config"))

local function install_parsers()
  local config = read_json(payload .. "/treesitter.json")
  local tree_path = data .. "/lazy/nvim-treesitter"
  ensure(vim.fn.sha256(read_text(tree_path .. "/lockfile.json")) == vim.fn.sha256(read_text(payload .. "/treesitter-lock.json")), "Treesitter grammar lock differs from snapshot")
  require("nvim-treesitter.configs").setup({ ensure_installed = {}, auto_install = false })
  vim.cmd("runtime plugin/nvim-treesitter.lua")
  local required = {}
  for _, lang in ipairs(config.parsers) do
    if #vim.api.nvim_get_runtime_file("parser/" .. lang .. ".so", false) == 0 then
      required[#required + 1] = lang
    end
  end
  if #required > 0 then
    print("Compiling missing frozen parsers: " .. table.concat(required, ", "))
    vim.cmd("TSInstallSync " .. table.concat(required, " "))
  else
    print("All frozen parsers are already installed; no grammar download or rebuild")
  end
  local missing = {}
  for _, lang in ipairs(config.parsers) do
    if #vim.api.nvim_get_runtime_file("parser/" .. lang .. ".so", false) == 0 then
      missing[#missing + 1] = lang
    end
  end
  ensure(#missing == 0, "Parsers failed to compile: " .. table.concat(missing, ", "))
  print("Verified " .. #config.parsers .. " parsers from the frozen grammar lock; compiled " .. #required .. " missing parsers")
end

local function install_mason()
  local config = read_json(payload .. "/mason.json")
  -- Seed the exact registry JSON locally; never refresh to today's registry.
  local registry_dir = data .. "/mason/registries/github/mason-org/mason-registry"
  vim.fn.mkdir(registry_dir, "p")
  for _, name in ipairs({ "registry.json", "info.json" }) do
    local source = payload .. "/mason-registry/" .. name
    local destination = registry_dir .. "/" .. name
    vim.fn.writefile(vim.fn.readfile(source, "b"), destination, "b")
  end
  local registry_data = read_text(registry_dir .. "/registry.json")
  ensure(vim.fn.sha256(registry_data) == config.registry.checksums["registry.json"], "Mason registry checksum mismatch")
  require("mason").setup({
    install_root_dir = data .. "/mason",
    registries = { config.registry.provider .. "@" .. config.registry.version },
  })
  local registry = require("mason-registry")
  local function current_version(name)
    local receipt = data .. "/mason/packages/" .. name .. "/mason-receipt.json"
    if vim.fn.filereadable(receipt) ~= 1 then return nil end
    local source = read_json(receipt).primary_source or {}
    return source.id and source.id:match("@([^#]+)") or nil
  end
  local platform = vim.env.NEOVIDE_BUNDLE_PLATFORM
    or (vim.fn.has("macunix") == 1 and "macos-arm64" or "linux-x86_64")
  local selected, skipped = {}, 0
  for _, item in ipairs(config.packages) do
    if not item.platforms or vim.tbl_contains(item.platforms, platform) then
      selected[#selected + 1] = item
    else
      skipped = skipped + 1
      print("Skipping optional " .. item.name .. "@" .. item.version .. " on " .. platform .. ": " .. (item.reason or "not selected for this platform"))
    end
  end
  for _, item in ipairs(selected) do
    local package = registry.get_package(item.name)
    if current_version(item.name) ~= item.version then
      print("Installing " .. item.name .. "@" .. item.version)
      local handle = package:install({ version = item.version, force = package:is_installed() })
      local output_tail = ""
      local function append_output(chunk)
        output_tail = (output_tail .. tostring(chunk)):sub(-6000)
      end
      -- Capture already-buffered early failures, then subscribe without
      -- printing normal download/build progress for successful packages.
      if handle.stdio and handle.stdio.buffers then
        for _, stream in ipairs({ "stdout", "stderr" }) do
          for _, chunk in ipairs(handle.stdio.buffers[stream] or {}) do
            append_output(chunk)
          end
        end
      end
      handle:on("stdout", append_output)
      handle:on("stderr", append_output)
      local function print_failure_tail()
        if output_tail ~= "" then
          vim.api.nvim_out_write("Mason " .. item.name .. " failure output (last 6000 bytes):\n" .. output_tail .. "\n")
        end
      end
      local finished = vim.wait(600000, function() return handle:is_closed() end, 100)
      if not finished then
        if not handle:is_closed() then handle:terminate() end
        print_failure_tail()
        error("Mason install timed out: " .. item.name)
      elseif current_version(item.name) ~= item.version then
        print_failure_tail()
        error("Mason exact-version install failed: " .. item.name .. "@" .. item.version)
      end
    end
    ensure(current_version(item.name) == item.version, "Mason exact-version install failed: " .. item.name .. "@" .. item.version)
  end
  print("Installed/verified " .. #selected .. " selected versioned tools from the frozen registry on " .. platform .. "; skipped " .. skipped .. " optional tools")
end

local function health()
  local native = require("fff.rust")
  ensure(type(native) == "table", "FFF native library did not load")
  local lua_snip = require("luasnip")
  ensure(type(lua_snip) == "table", "LuaSnip did not load")
  ensure(vim.fn.executable("node") == 1, "node is missing from PATH")
  local converter = data .. "/latex2text-venv/bin/latex2text"
  ensure(vim.fn.executable(converter) == 1, "Pinned pylatexenc converter is missing")
  ensure(vim.fn.filereadable(data .. "/codex-acp/package-lock.json") == 1, "Codex ACP package lock is missing")
  print("Core native plugins, Node, ACP lock and LaTeX converter are present")
end

local ok, err = xpcall(function()
  if phase == "parsers" then install_parsers()
  elseif phase == "mason" then install_mason()
  elseif phase == "health" then health()
  else error("Unknown NVIM_BUNDLE_PHASE: " .. phase) end
end, debug.traceback)
if not ok then
  vim.api.nvim_err_writeln(err)
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
