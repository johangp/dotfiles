local options = {
  formatters_by_ft = {
    lua = { "stylua" },
    python = { "ruff_format", "isort", "ruff_fix" },
    json = { "prettier" },
    bash = { "beautysh" },
    hcl = { "hclfmt" },
    terraform = { "terraform_fmt" },
    -- html = { "prettier" },
  },

  -- format_on_save = {
  --   -- These options will be passed to conform.format()
  --   timeout_ms = 500,
  --   lsp_fallback = true,
  -- },
}

return options
