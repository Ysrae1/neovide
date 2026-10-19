-- nvim --headless -u NONE -l tests/media/image_transport.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
vim.opt.rtp:prepend(vim.env.GLOW_TEST_CONFIG or root .. "/portable/payload/nvim")
local transport = require("config.media.image_transport")
local received = {}
for owner, module in pairs({ image = "image", molten = "molten_images", yazi = "yazi" }) do
  package.loaded["config.media." .. module] = {
    on_status = function(...)
      received[#received + 1] = { owner = owner, args = { ... } }
    end,
  }
end
local function dispatch(id, owner)
  local before = #received
  transport.on_status(id, 13, 17, "failure")
  assert(#received == before + 1 and received[#received].owner == owner, "route " .. tostring(id))
  assert(vim.deep_equal(received[#received].args, { id, 13, 17, "failure" }), "status payload")
end
for _, pair in ipairs({ { 1, "image" }, { 999999, "image" }, { 1000001, "molten" },
  { 1999999, "molten" }, { 2000001, "yazi" }, { 9007199254740991, "yazi" } }) do
  dispatch(pair[1], pair[2])
end
local before = #received
for _, invalid in ipairs({ -1, 0, 1000000, 2000000, 1.5, "1", math.huge, 9007199254740992 }) do
  transport.on_status(invalid, 0, 0, nil)
end
transport.on_status(nil)
assert(#received == before, "invalid and reserved IDs are never delivered")
assert(not pcall(transport.allocate, "unknown"), "unknown owner rejected")
for _, pair in ipairs({ { "image", 1, 999999 }, { "molten", 1000001, 1999999 } }) do
  for id = pair[2], pair[3] do
    assert(transport.allocate(pair[1]) == id, "monotonic unique IDs")
  end
  local id, err = transport.allocate(pair[1])
  assert(id == nil and type(err) == "string", "exhaustion cannot cross into another owner")
  assert(transport.allocate(pair[1]) == nil, "exhaustion never wraps or reuses a queued ID")
end
assert(transport.allocate("yazi") == 2000001 and transport.allocate("yazi") == 2000002,
  "one exhausted owner does not exhaust other owners")
local callback = assert(loadfile(root .. "/lua/image_status.lua"))
local before_callback = #received
callback(1, 13, 17, "failure")
assert(#received == before_callback, "GUI status delivery stays asynchronous")
assert(vim.wait(1000, function() return #received == before_callback + 1 end), "new configuration callback")
assert(received[#received].owner == "image", "new callback owner")
-- A previous configuration has no transport module. The GUI must keep its
-- existing receivers working when only the binary was upgraded.
package.loaded["config.media.image_transport"] = nil
package.preload["config.media.image_transport"] = function() error("old configuration") end
for _, pair in ipairs({ { 1, "image" }, { 1000001, "molten" }, { 2000001, "yazi" } }) do
  local count = #received
  callback(pair[1], 13, 17, "failure")
  assert(vim.wait(1000, function() return #received == count + 1 end), "legacy callback")
  assert(received[#received].owner == pair[2], "legacy owner")
end
package.loaded["config.media.yazi"] = { on_status = false }
transport.on_status(2000001)
print("Image transport: routing, payload, ID exhaustion and owner isolation passed")
vim.cmd.qa()
