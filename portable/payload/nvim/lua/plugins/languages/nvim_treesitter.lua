return {
  {
    "nvim-treesitter/nvim-treesitter",
    -- Keep the existing configs API and its matching grammar revisions.
    branch = "master",
    pin = true,
    build = false, -- Parser sources are frozen and compiled by the installer.
    config = function()
      local configs = require("nvim-treesitter.configs")

      configs.setup({
        ensure_installed = {}, -- Installed explicitly by the portable bootstrap.
        auto_install = false,
        sync_install = false,
        -- VimTeX supplies TeX highlighting and formula conceal replacements.
        -- Keep the parser for Markdown math injections and folding only.
        highlight = { enable = true, disable = { "neo-tree", "latex" } },
        indent = { enable = true },
      })

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("UserTreesitterFolds", { clear = true }),
        pattern = "*",
        callback = function()
          vim.wo.foldmethod = "expr"
          vim.wo.foldexpr = "nvim_treesitter#foldexpr()"
          vim.wo.foldenable = true
        end,
      })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "master",
    pin = true,
    -- LazyVim now targets the new API; retain the installed module API.
    config = function(_, opts)
      local move = vim.deepcopy(opts.move or {})
      local keys = move.keys or {}
      move.keys = nil
      for method, keymaps in pairs(keys) do
        move[method] = keymaps
      end
      require("nvim-treesitter.configs").setup({ textobjects = { move = move } })
    end,
  },
}
