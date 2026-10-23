-- Isolated standard theme modules and reloads. No GUI or user files touched.
local config = assert(vim.env.GLOW_TEST_CONFIG)
vim.opt.rtp = { config, vim.env.VIMRUNTIME }
local root = vim.fs.normalize(vim.fn.tempname()) .. '-windows-themes'
local has, stdpath, appdata = vim.fn.has, vim.fn.stdpath, vim.env.LOCALAPPDATA
local platform, active_config = 'mac', config
vim.fn.has = function(name)
  if name == 'win32' then return platform == 'windows' and 1 or 0 end
  return has(name)
end
vim.fn.stdpath = function(name)
  return name == 'config' and active_config or stdpath(name)
end
vim.env.LOCALAPPDATA = root .. '/AppData/Local'
vim.g.neovide = true
package.loaded['config.integrations.github'] = { setup = function() end }
package.loaded['config.appearance.window_drag'] = { setup = function() end }
local receipt = { state = 'started', config = config, cases = {} }
local function module_name(mode) return 'config.appearance.themes.ayu_' .. mode .. '_customed' end
local function clear_themes()
  for _, mode in ipairs({ 'light', 'dark' }) do package.loaded[module_name(mode)] = nil end
end
local function theme_file(directory, mode) return directory .. '/ayu_' .. mode .. '_customed.lua' end
local function write_theme(directory, mode, value)
  vim.fn.mkdir(directory, 'p')
  vim.fn.writefile(vim.split('return ' .. vim.inspect(value), '\n', { plain = true }), theme_file(directory, mode))
end
local ok, err = xpcall(function()
  local themes = {}
  for _, mode in ipairs({ 'light', 'dark' }) do themes[mode] = require(module_name(mode)) end
  local chad = assert(loadfile(config .. '/lua/chadrc.lua'))()
  assert(package.loaded['config.platform.windows_themes'] == nil, 'Mac imported Windows theme loader')
  assert(chad.base46.changed_themes.ayu_light == themes.light and chad.base46.changed_themes.ayu_dark == themes.dark,
    'Mac no longer uses its original theme tables')
  local loader = require('config.platform.windows_themes')
  assert(loader.directory() == nil and loader.reload() == false, 'non-Windows has local side effects')
  assert(loader.load('ayu_light_customed') == themes.light)
  receipt.cases[#receipt.cases + 1] = 'Mac original theme identity and reload behavior unchanged'

  local legacy_directory = vim.fs.joinpath(vim.env.LOCALAPPDATA, 'NeovideGlow', 'appearance', 'themes')
  for _, mode in ipairs({ 'light', 'dark' }) do write_theme(legacy_directory, mode, { legacy = true }) end
  local legacy_bytes = vim.fn.readfile(theme_file(legacy_directory, 'light'), 'b')
  local calls = 0
  package.loaded.base46 = { load_all_highlights = function() calls = calls + 1 end }
  platform = 'windows'
  -- ConfigRedirect makes stdpath(config) the user's home configuration. A fresh,
  -- unredirected package instead selects its own profile/config/nvim.
  for _, location in ipairs({ 'home/.config/nvim', 'profile/config/nvim' }) do
    active_config = root .. '/' .. location
    local directory = active_config .. '/lua/config/appearance/themes'
    vim.opt.rtp = { active_config, config, vim.env.VIMRUNTIME }
    assert(loader.directory() == directory, 'loader disagrees with the active configuration')
    local expected = {}
    for _, mode in ipairs({ 'light', 'dark' }) do
      expected[mode] = vim.deepcopy(themes[mode])
      expected[mode].base_30.folder_bg = mode == 'light' and '#F2F2F3' or '#123456'
      expected[mode].polish_hl['neo-tree'].NeoTreeCursorLine.blend = mode == 'light' and 15 or 23
      write_theme(directory, mode, expected[mode])
    end
    clear_themes()
    chad = assert(loadfile(config .. '/lua/chadrc.lua'))()
    for _, mode in ipairs({ 'light', 'dark' }) do
      assert(vim.deep_equal(chad.base46.changed_themes['ayu_' .. mode], expected[mode]), 'Windows full theme changed')
    end
    assert(themes.light.base_30.folder_bg ~= expected.light.base_30.folder_bg, 'shared Mac palette mutated')
    package.loaded.nvconfig = { base46 = chad.base46 }
    local saved_bytes = vim.fn.readfile(theme_file(directory, 'light'), 'b')
    local previous_calls = calls
    assert(loader.reload() and calls == previous_calls + 1)
    assert(vim.deep_equal(package.loaded.nvconfig.base46.changed_themes.ayu_light, expected.light))
    assert(vim.deep_equal(saved_bytes, vim.fn.readfile(theme_file(directory, 'light'), 'b')), 'reload rewrote user theme')

    -- Exact route documented at the top of both theme files, with a saved edit.
    expected.dark.base_30.folder_bg = '#47525C'
    write_theme(directory, 'dark', expected.dark)
    package.loaded[module_name('dark')] = nil
    package.loaded.nvconfig.base46.changed_themes.ayu_dark = require(module_name('dark'))
    require('base46').load_all_highlights()
    assert(vim.deep_equal(loader.load('ayu_dark_customed'), expected.dark), 'header reload and loader read different files')
    assert(vim.deep_equal(package.loaded.nvconfig.base46.changed_themes.ayu_dark, expected.dark), 'header reload ignored saved edit')
    receipt.cases[#receipt.cases + 1] = location .. ': complete Light/Dark modules, folder_bg, both reload routes and legacy AppData ignored'
  end
  assert(vim.deep_equal(legacy_bytes, vim.fn.readfile(theme_file(legacy_directory, 'light'), 'b')), 'legacy backup changed')
  local local_file = loader.directory() .. '/ayu_light_customed.lua'
  vim.fn.writefile({ 'this is invalid Lua' }, local_file)
  clear_themes()
  local loaded, message = pcall(loader.load, 'ayu_light_customed')
  assert(not loaded and tostring(message):find('ayu_light_customed.lua', 1, true), 'invalid user palette silently replaced')
  assert(vim.fn.readfile(local_file)[1] == 'this is invalid Lua', 'invalid user palette overwritten')
  receipt.cases[#receipt.cases + 1] = 'invalid user theme reported and preserved without fallback to legacy AppData'

  platform, active_config = 'mac', config
  vim.opt.rtp = { config, vim.env.VIMRUNTIME }
  clear_themes()
  chad = assert(loadfile(config .. '/lua/chadrc.lua'))()
  assert(vim.deep_equal(chad.base46.changed_themes.ayu_light, themes.light), 'Windows settings leaked to Mac')
  local previous_calls = calls
  assert(loader.reload() == false and calls == previous_calls)
  receipt.cases[#receipt.cases + 1] = 'Mac keeps its own unchanged theme values after Windows fixtures'
  receipt.state = 'passed'
end, debug.traceback)
vim.fn.has, vim.fn.stdpath, vim.env.LOCALAPPDATA = has, stdpath, appdata
vim.fn.delete(root, 'rf')
if not ok then receipt.state = 'failed'; receipt.error = err end
if vim.env.GLOW_TEST_RECEIPT then vim.fn.writefile({ vim.json.encode(receipt) }, vim.env.GLOW_TEST_RECEIPT) end
assert(ok, err)
print('PASS isolated Windows themes: active config modules and both reload routes; legacy AppData ignored; Mac values unchanged')
vim.cmd('qa!')
