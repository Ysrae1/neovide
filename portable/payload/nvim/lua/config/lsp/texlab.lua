return {
  settings = {
    texlab = {
      build = {
        executable = "latexmk",
        args = {
          "-xelatex",
          "-file-line-error",
          "-interaction=nonstopmode",
          "-synctex=1",
          "%f",
        },
        forwardSearchAfter = false,
        onSave = true,
      },
      forwardSearch = vim.fn.has("macunix") == 1 and {
        executable = "/Applications/Skim.app/Contents/SharedSupport/displayline",
        args = { "%l", "%p", "%f" },
      } or nil,
      chktex = {
        onEdit = true,
        onOpenAndSave = true,
      },
      bibtexFormatter = "texlab",
    },
  },
}
