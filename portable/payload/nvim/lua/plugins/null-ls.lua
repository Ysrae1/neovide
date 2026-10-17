return {
  {
    "nvimtools/none-ls.nvim",
    dependencies = { "mason.nvim", "gbprod/none-ls-shellcheck.nvim" },
    opts = function(_, opts)
      local null_ls = require("null-ls")
      local formatting = null_ls.builtins.formatting
      local diagnostics = null_ls.builtins.diagnostics

      -- Mason adds its bin directory to PATH. Package.path is not an executable.
      -- Missing optional tools should not cause an error when a file is opened.
      local function available(source, command, source_opts)
        source_opts = source_opts or {}
        source_opts.command = command
        source_opts.condition = function()
          return vim.fn.executable(command) == 1
        end
        return source.with(source_opts)
      end

      opts.debug = false
      opts.sources = {
        available(diagnostics.mypy, "mypy"),
        available(diagnostics.yamllint, "yamllint"),
        available(formatting.black, "black"),
        available(formatting.stylua, "stylua", {
          extra_args = { "--indent-type", "Spaces", "--indent-width", "2" },
        }),
        available(formatting.shfmt, "shfmt"),
        available(formatting.prettierd, "prettierd"),
        available(require("none-ls-shellcheck.diagnostics"), "shellcheck"),
        available(require("none-ls-shellcheck.code_actions"), "shellcheck"),
      }
      return opts
    end,
  },
}
