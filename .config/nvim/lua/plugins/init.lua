return {
  {
    "LazyVim/LazyVim",
    lazy = true,
    config = function()
      require "lazyvim.util"
    end,
  },
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  {
    "tpope/vim-fugitive",
    lazy = false,
  },

  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      -- add tsx and treesitter
      vim.list_extend(opts.ensure_installed, {
        "bash",
        "hcl",
        "json",
        "markdown",
        "markdown_inline",
        "python",
        "terraform",
        "yaml",
      })
    end,
  },
  {
    "sindrets/diffview.nvim",
    lazy = false,
  },
}
