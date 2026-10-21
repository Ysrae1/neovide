-- GLOW_TEST_CONFIG=/path/to/nvim nvim --headless --noplugin -u NONE -i NONE
--   -l tests/navigation/github_account.lua
-- Uses only temporary account preferences and mocks all browser/auth/network calls.
local config = assert(vim.env.GLOW_TEST_CONFIG, "GLOW_TEST_CONFIG is required")
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
local state = vim.fn.tempname()
local original = {
  stdpath = vim.fn.stdpath, executable = vim.fn.executable, system = vim.system,
  open = vim.ui.open, jobstart = vim.fn.jobstart, notify = vim.notify,
}
vim.fn.stdpath = function(name) return name == "state" and state or original.stdpath(name) end
local calls, notices, have_gh = {}, {}, false
vim.notify = function(message) notices[#notices + 1] = message end
vim.fn.executable = function(name) return name == "gh" and (have_gh and 1 or 0) or original.executable(name) end
vim.system = function(args, _, done)
  calls[#calls + 1] = args
  assert(vim.deep_equal(args, { "gh", "api", "user", "--hostname", "github.com", "--jq", ".login" }))
  done({ code = 0, stdout = "octocat\n" })
end
vim.fn.jobstart = function(args, opts)
  calls[#calls + 1] = args
  assert(vim.deep_equal(args, { "gh", "auth", "login", "--hostname", "github.com", "--web" }))
  assert(opts.term == true, "login must use an interactive terminal")
  return 42
end
package.preload["nvchad.tabufline.utils"] = function()
  return { btn = function(text, hl, action)
    assert(hl == "TabCloseBtn" and action == "OpenGitHubProfile", "badge style/callback changed")
    return text
  end }
end

local ok, err = xpcall(function()
  local github = require("config.integrations.github")
  github.setup()
  github.setup()
  assert(github.get_user() == nil and github.badge() == "  GitHub ", "fresh installs must be generic")
  assert(github.profile_url() == "https://github.com")
  assert(#calls == 0, "load/render/setup must never start network or authentication")
  assert(vim.fn.filereadable(state .. "/glow/github.json") == 0, "render must not create state")
  assert(github.normalize(" https://github.com/octo-cat/ ") == "octo-cat")
  for _, value in ipairs({ "-octo", "octo-", "octo--cat", "octo/cat", "https://evil.test/octocat", "octo%cat",
    "octo?x=1", "octo\ncat", string.rep("a", 40), "https://github.com/octo/repo" }) do
    assert(github.normalize(value) == nil, "unsafe/invalid profile accepted: " .. value)
  end
  assert(github.set_user("https://github.com/Octo-cat/"))
  assert(github.profile_url() == "https://github.com/Octo-cat")
  assert(github.badge() == "  Octo-cat ")
  package.loaded["config.integrations.github"] = nil
  github = require("config.integrations.github")
  assert(github.get_user() == "Octo-cat", "preference did not survive module/session reload")
  local opened
  vim.ui.open = function(url) opened = url end
  github.open()
  assert(opened == "https://github.com/Octo-cat", "browser URL changed")
  github.import_user()
  github.login()
  assert(#calls == 0 and #notices == 2, "missing gh must explain availability without launching anything")
  have_gh = true
  github.import_user()
  assert(vim.wait(1000, function() return github.get_user() == "octocat" end))
  assert(#calls == 1, "account import must run only on explicit request")
  github.login()
  assert(#calls == 2, "explicit login must launch exactly one interactive gh process")
  assert(github.set_user(nil) and github.get_user() == nil)
  package.loaded["config.integrations.github"] = nil
  github = require("config.integrations.github")
  assert(github.badge() == "  GitHub " and #calls == 2, "cleared preference must reload without auth side effects")
  vim.fn.writefile({ "not json" }, state .. "/glow/github.json")
  package.loaded["config.integrations.github"] = nil
  assert(require("config.integrations.github").get_user() == nil, "bad state must safely use default")
  print("PASS GitHub account: generic default, validated URL/user, persistent preference, explicit import/login, no startup side effects")
end, debug.traceback)

vim.fn.stdpath, vim.fn.executable, vim.system = original.stdpath, original.executable, original.system
vim.ui.open, vim.fn.jobstart, vim.notify = original.open, original.jobstart, original.notify
vim.fn.delete(state, "rf")
if not ok then error(err) end
