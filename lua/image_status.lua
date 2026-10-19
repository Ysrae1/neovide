-- Keep status dispatch in the companion configuration. Older configurations
-- still receive callbacks using their original reserved image ID ranges.
local args = { ... }
vim.schedule(function()
    local ok, transport = pcall(require, "config.media.image_transport")
    if ok and type(transport.on_status) == "function" then
        transport.on_status(unpack(args))
        return
    end
    local module = args[1] >= 2000000 and "config.media.yazi"
        or args[1] >= 1000000 and "config.media.molten_images" or "config.media.image"
    local loaded, receiver = pcall(require, module)
    if loaded and type(receiver.on_status) == "function" then receiver.on_status(unpack(args)) end
end)
