local width, height = ...
if type(width) ~= 'number' or type(height) ~= 'number' or width <= 0 or height <= 0
  or width ~= width or height ~= height or width == math.huge or height == math.huge then
  return
end
if vim.g.neovide_cell_width == width and vim.g.neovide_cell_height == height then return end
vim.g.neovide_cell_width, vim.g.neovide_cell_height = width, height
local images = package.loaded['config.media.molten_images']
if images and images.on_cell_metrics then images.on_cell_metrics(width, height) end
