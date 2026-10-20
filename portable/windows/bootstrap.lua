-- Build-worker only. Native Windows dependencies are prepared before packaging;
-- installed users never run this script or download/compile missing components.
local function ensure(condition, message) if not condition then error(message, 0) end end
local function read_text(path) return table.concat(vim.fn.readfile(path, "b"), "\n") end
local function read_json(path) return vim.json.decode(read_text(path)) end

local function main()
  ensure(vim.fn.has("win32") == 1, "Windows bootstrap requires native Windows Neovim")
  ensure(vim.env.NEOVIDE_BUNDLE_PLATFORM == "windows-x64", "Expected NEOVIDE_BUNDLE_PLATFORM=windows-x64")
  local payload = assert(vim.env.NEOVIDE_BUNDLE_PAYLOAD, "NEOVIDE_BUNDLE_PAYLOAD is required")
  local phase = vim.env.NVIM_BUNDLE_PHASE
  ensure(phase == "parsers" or phase == "mason" or phase == "health", "Windows bootstrap phase must be parsers, mason or health")
  local data = vim.fn.stdpath("data")
  for _, plugin in ipairs(read_json(payload .. "/plugins.json").plugins) do
    local directory = data .. "/lazy/" .. plugin.name
    ensure(vim.fn.isdirectory(directory) == 1, "Missing frozen plugin: " .. directory)
    vim.opt.runtimepath:append(directory)
  end
  vim.opt.runtimepath:prepend(vim.fn.stdpath("config"))

  if phase == "health" then
    dofile(assert(vim.env.NEOVIDE_GLOW_INIT, "NEOVIDE_GLOW_INIT is required for packaged runtime health"))
    local runtime = require("config.media.runtime")
    ensure(runtime.ready(), "Bundled Python/Jupytext launchers are not ready")
    ensure(vim.g.python3_host_prog == runtime.python(), "Notebook provider is not using the packaged Python")
    ensure(vim.fn.executable(vim.env.GLOW_LATEX2TEXT or "") == 1, "Packaged LaTeX converter is missing")
    ensure(vim.fn.executable("node") == 1, "Packaged Node runtime is missing from PATH")
    ensure(vim.fn.filereadable(data .. "/codex-acp/package-lock.json") == 1, "Frozen Codex ACP lock is missing")
    local imports = vim.fn.system({ runtime.python(), "-c", "import pynvim,jupyter_client,jupytext,nbformat,PIL,matplotlib,pylatexenc;print('ok')" })
    ensure(vim.v.shell_error == 0, "Bundled Python imports failed: " .. imports)
    ensure(type(require("fff.rust")) == "table", "FFF native Windows DLL did not load")
    local compile = require("luasnip.util.jsregexp")
    ensure(type(compile) == "function", "LuaSnip native Windows jsregexp did not load")
    local regexp = assert(compile("glow", "i"))
    ensure(regexp:match("Glow")[0] == "Glow", "LuaSnip Windows regex evaluation failed")
    local fzf = require("fzf_lib")
    local pattern, slab = fzf.parse_pattern("glw"), fzf.allocate_slab()
    local score = fzf.get_score("Glow", pattern, slab)
    fzf.free_pattern(pattern); fzf.free_slab(slab)
    ensure(score > 0, "Telescope native Windows fzf scoring failed")
    for _, name in ipairs({ "avante_tokenizers", "avante_templates", "avante_repo_map", "avante_html2md" }) do
      local loader, err = package.loadlib(data .. "/lazy/avante.nvim/build/" .. name .. ".dll", "luaopen_" .. name)
      ensure(type(loader) == "function", "Avante native Windows DLL failed: " .. name .. ": " .. tostring(err))
      ensure(type(loader()) == "table", "Avante Windows module did not initialize: " .. name)
    end
    print("Windows health passed: FFF, LuaSnip, Telescope and 4 Avante DLLs loaded; bundled Python imports/CLI paths verified; no kernel started")
    return
  end

  if phase == "parsers" then
    local frozen = read_json(payload .. "/treesitter.json")
    local lock = read_json(payload .. "/treesitter-lock.json")
    local directory = data .. "/lazy/nvim-treesitter"
    ensure(vim.fn.sha256(read_text(directory .. "/lockfile.json")) == vim.fn.sha256(read_text(payload .. "/treesitter-lock.json")),
      "Treesitter grammar lock differs from the frozen payload")
    local parsers = require("nvim-treesitter.parsers").get_parser_configs()
    ensure(parsers.jsonc.install_info.url == "https://gitlab.com/WhyNotHugo/tree-sitter-jsonc.git"
      and lock.jsonc.revision == "02b01653c8a1c198ae7287d566efa86a135b30d5", "Unexpected frozen JSONC source/revision")
    local install = require("nvim-treesitter.install")
    -- GitLab archive responses were unreliable in the WSL test. Clone the same
    -- frozen grammar revision; no source URL or revision is substituted.
    install.prefer_git = true
    local compilers = {}
    if vim.env.CC and vim.env.CC ~= "" then
      local compiler = vim.env.CC:gsub("\\", "/"):match("([^/]+)$"):lower()
      ensure(vim.tbl_contains({ "cl", "cl.exe", "clang-cl", "clang-cl.exe" }, compiler), "Windows parser CC must be cl or clang-cl")
      compilers[#compilers + 1] = vim.env.CC
    end
    vim.list_extend(compilers, { "cl", "clang-cl" })
    install.compilers = vim.tbl_filter(function(name) return vim.fn.executable(name) == 1 end, compilers)
    ensure(#install.compilers > 0, "An x64 MSVC developer environment with cl or clang-cl is required")
    ensure(not vim.env.VSCMD_ARG_TGT_ARCH or vim.env.VSCMD_ARG_TGT_ARCH == "x64", "Parser compiler must target x64")
    ensure(vim.fn.executable("git") == 1 and vim.fn.executable("tree-sitter") == 1, "Pinned Git/tree-sitter tools are missing")
    require("nvim-treesitter.configs").setup({ ensure_installed = {}, auto_install = false })
    vim.cmd("runtime plugin/nvim-treesitter.lua")
    local missing = {}
    for _, language in ipairs(frozen.parsers) do
      -- The pinned nvim-treesitter loader uses .so even for PE Windows DLLs.
      if vim.fn.filereadable(directory .. "/parser/" .. language .. ".so") ~= 1 then missing[#missing + 1] = language end
    end
    if #missing > 0 then vim.cmd("TSInstallSync " .. table.concat(missing, " ")) end
    for _, language in ipairs(frozen.parsers) do
      local path = directory .. "/parser/" .. language .. ".so"
      ensure(vim.fn.filereadable(path) == 1, "Frozen parser was not compiled: " .. language)
      local loaded, err = pcall(vim.treesitter.language.add, language, { path = path })
      ensure(loaded and err ~= false, "Windows parser ABI check failed for " .. language .. ": " .. tostring(err))
    end
    print("Verified " .. #frozen.parsers .. " frozen Windows parser DLLs; compiled " .. #missing)
    return
  end

  local config = read_json(payload .. "/mason.json")
  local registry_dir = data .. "/mason/registries/github/mason-org/mason-registry"
  vim.fn.mkdir(registry_dir, "p")
  for _, name in ipairs({ "registry.json", "info.json" }) do
    ensure(vim.fn.writefile(vim.fn.readfile(payload .. "/mason-registry/" .. name, "b"), registry_dir .. "/" .. name, "b") == 0,
      "Cannot seed the frozen Mason registry")
  end
  ensure(vim.fn.sha256(read_text(registry_dir .. "/registry.json")) == config.registry.checksums["registry.json"], "Mason registry checksum mismatch")
  require("mason").setup({ install_root_dir = data .. "/mason", registries = { config.registry.provider .. "@" .. config.registry.version } })
  local registry = require("mason-registry")
  local parser = require("mason-core.installer.registry")
  ensure(require("mason-core.platform").is.win_x64, "Mason must detect native Windows x64")
  local function current_version(name)
    local receipt = data .. "/mason/packages/" .. name .. "/mason-receipt.json"
    if vim.fn.filereadable(receipt) ~= 1 then return nil end
    local source = read_json(receipt).primary_source or {}
    return source.id and source.id:match("@([^#]+)") or nil
  end
  -- Older manifest platform annotations describe the Mac/WSL selection, not
  -- upstream Windows support. Ask the frozen registry at each pinned version.
  -- A required unsupported package is an error, never a silent omission.
  local selected = {}
  for _, item in ipairs(config.packages) do
    local package = registry.get_package(item.name)
    local supported, err = pcall(function()
      -- Let Mason match general `win` assets as well as `win_x64` assets.
      -- Its explicit target option requires an exact tuple and rejects ltex-ls.
      return parser.parse(package.spec, { version = item.version, strict = true }):get_or_throw()
    end)
    ensure(supported, "Required frozen Windows tool is unsupported: " .. item.name .. "@" .. item.version .. ": " .. tostring(err))
    selected[#selected + 1] = { item = item, package = package }
  end
  for _, selection in ipairs(selected) do
    local item, package = selection.item, selection.package
    if current_version(item.name) ~= item.version then
      print("Installing frozen Windows tool " .. item.name .. "@" .. item.version)
      local handle = package:install({ version = item.version, strict = true, force = package:is_installed() })
      local tail = ""
      local function append(chunk) tail = (tail .. tostring(chunk)):sub(-6000) end
      if handle.stdio and handle.stdio.buffers then
        for _, stream in ipairs({ "stdout", "stderr" }) do for _, chunk in ipairs(handle.stdio.buffers[stream] or {}) do append(chunk) end end
      end
      handle:on("stdout", append); handle:on("stderr", append)
      local finished = vim.wait(600000, function() return handle:is_closed() end, 100)
      if not finished and not handle:is_closed() then handle:terminate() end
      ensure(finished and current_version(item.name) == item.version,
        "Frozen Windows tool install failed: " .. item.name .. "@" .. item.version .. "\n" .. tail)
    end
    ensure(current_version(item.name) == item.version, "Installed tool version mismatch: " .. item.name)
  end
  print("Verified " .. #selected .. " frozen Windows Mason tools; no required package skipped")
end

local ok, err = xpcall(main, debug.traceback)
if not ok then vim.api.nvim_err_writeln(err); vim.cmd("cquit 1") else vim.cmd("qa!") end
