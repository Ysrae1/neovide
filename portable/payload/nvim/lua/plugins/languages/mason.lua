return {
  {
    "mason-org/mason.nvim",
    build = false,
    opts = {
      ensure_installed = {},
      registries = { "github:mason-org/mason-registry@2026-05-22-fiscal-eon" },
      ui = {
        border = "rounded",
        icons = { package_installed = "󰄬", package_pending = "󰁔", package_uninstalled = "󰅖" },
      },
    },
    config = function(_, opts)
      -- Installation is owned by the fixed-version portable bootstrap.
      require("mason").setup(opts)
    end,
  },
}
