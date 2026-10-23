-- Native DLL contract probe; no user config, credentials, AI requests, or GUI.
-- Run through an isolated Windows ARM64 Neovim with the GLOW_TEST_* paths set.
local work = assert(vim.env.GLOW_TEST_NATIVE_WORK)
local receipt = assert(vim.env.GLOW_TEST_NATIVE_RECEIPT)
local plugin_dir = assert(vim.env.GLOW_TEST_PLUGIN_DIR):gsub("\\", "/")
vim.fn.mkdir(work, "p")
local result = { state = "running", architecture = jit.arch, tests = {}, no_ai_requests = true }
local function check(name, fn)
  local ok, value = pcall(fn)
  result.tests[#result.tests + 1] = { name = name, passed = ok, detail = ok and value or tostring(value) }
  if not ok then error(name .. ": " .. tostring(value)) end
end
local function load_native(name, explicit)
  if explicit then return assert(package.loadlib(explicit, "luaopen_" .. name))() end
  return require(name)
end
local fff
local ok, err = pcall(function()
  assert(jit.arch == "arm64", "Probe must run under ARM64 Neovim")
  local enabled = vim.env.GLOW_TEST_NATIVE_PLUGINS or "fff,avante"
  if enabled:find("fff", 1, true) then
    vim.opt.rtp:prepend(plugin_dir .. "/fff")
    check("fff native load and health", function()
      fff = vim.env.GLOW_TEST_FFF_DLL and load_native("fff_nvim", vim.env.GLOW_TEST_FFF_DLL) or require("fff.rust")
      local health = fff.health_check(work)
      assert(health.version == "0.11.0", vim.inspect(health))
      assert(health.git.available == true)
      return health
    end)
    check("fff native scan and fuzzy search", function()
      local fixture = work .. "/search"
      vim.fn.mkdir(fixture, "p")
      vim.fn.writefile({ "native ARM64 fixture" }, fixture .. "/glow_arm64_probe.txt")
      vim.fn.writefile({ "中文路径" }, fixture .. "/中文样例.txt")
      assert(fff.init_file_picker(fixture, { follow_symlinks = false }))
      assert(fff.wait_for_initial_scan(5000), "Initial fixture scan timed out")
      local found = fff.fuzzy_search_files("glow_arm64_probe", 1, nil, 4, 3, 0, 20)
      assert(found.total_matched >= 1, vim.inspect(found))
      assert(vim.inspect(found):find("glow_arm64_probe.txt", 1, true), vim.inspect(found))
      local chinese = fff.fuzzy_search_files("中文样例", 1, nil, 4, 3, 0, 20)
      assert(chinese.total_matched >= 1, vim.inspect(chinese))
      return { ascii = found.total_matched, chinese = chinese.total_matched }
    end)
  end
  if enabled:find("avante", 1, true) then
    vim.opt.rtp:prepend(plugin_dir .. "/avante.nvim")
    local native = (vim.env.GLOW_TEST_AVANTE_DIR or (plugin_dir .. "/avante.nvim/build")):gsub("\\", "/")
    package.cpath = native .. "/?.dll;" .. package.cpath
    check("avante tokenizer native encode", function()
      local tokenizer = require("avante_tokenizers")
      tokenizer.from_pretrained("gpt-4o") -- tiktoken data is embedded; no download.
      local tokens, count, chars = tokenizer.encode("Glow ARM64 中文")
      assert(type(tokens) == "table" and #tokens > 0 and count > 0 and chars > 0)
      return { token_count = count, characters = chars }
    end)
    check("avante template native render", function()
      local templates = require("avante_templates")
      local fixture = work .. "/templates"
      vim.fn.mkdir(fixture, "p")
      vim.fn.writefile({ "Glow {{ code_lang }}" }, fixture .. "/probe.jinja")
      templates.initialize(fixture, fixture)
      local rendered = templates.render("probe.jinja", { ask = true, code_lang = "ARM64" })
      assert(rendered:find("Glow ARM64", 1, true), rendered)
      return rendered
    end)
    check("avante repo map native parse", function()
      local definitions = require("avante_repo_map").stringify_definitions("lua", "local function glow_native_probe(a)\n return a\nend\n")
      assert(definitions:find("glow_native_probe", 1, true), definitions)
      return definitions
    end)
    check("avante html conversion native API", function()
      local markdown = require("avante_html2md").html2md("<h1>Glow ARM64</h1><p>中文 <strong>native</strong></p>")
      assert(markdown:find("Glow ARM64", 1, true) and markdown:find("中文", 1, true), markdown)
      return markdown
    end)
  end
end)
if fff then
  local cleanup_ok, value = pcall(fff.cleanup_file_picker)
  result.cleanup = { passed = cleanup_ok, returned = value }
  if not cleanup_ok then ok, err = false, value end
end
result.state = ok and "passed" or "failed"
result.error = not ok and tostring(err) or nil
vim.fn.writefile({ vim.json.encode(result) }, receipt)
if not ok then io.stderr:write(tostring(err) .. "\n") end
vim.cmd(ok and "qa!" or "cquit 1")
