-- Apply the installed loading fix without replacing existing Notebook sessions,
-- restarting kernels, clearing readers, or touching the current buffer's text.
local directory = vim.fn.stdpath("config") .. "/lua/config/media/"
local runtime = require("config.media.runtime")
local fresh_runtime = assert(loadfile(directory .. "runtime/init.lua"))()
runtime.complete_notebook_load = fresh_runtime.complete_notebook_load
runtime.install_reader_guard = fresh_runtime.install_reader_guard
local wrapped = runtime.install_reader_guard()
local notebook = package.loaded["config.media.notebook_edit"]
if notebook then
  local fresh = assert(loadfile(directory .. "notebook_edit.lua"))()
  local previous, values = notebook.open, {}
  for index = 1, 100 do
    local name, value = debug.getupvalue(previous, index)
    if not name then break end
    values[name] = value
  end
  for index = 1, 100 do
    local name = debug.getupvalue(fresh.open, index)
    if not name then break end
    if values[name] ~= nil then debug.setupvalue(fresh.open, index, values[name]) end
  end
  notebook.open = fresh.open
end
return { readers_wrapped = wrapped, session_preserved = notebook ~= nil }
