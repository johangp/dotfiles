-- Use NvChad defaults (diagnostics, capabilities, lua_ls, etc.)
require("nvchad.configs.lspconfig").defaults()

-- list the servers you want
local servers = { "lua_ls", "ts_ls", "pyright", "html", "cssls", "terraform-ls" }

-- enable them via the new API
vim.lsp.enable(servers)
