return {
  "nvim-neotest/neotest",
  dependencies = {
    "nvim-neotest/nvim-nio",
    "nvim-neotest/neotest-python",
    "nvim-lua/plenary.nvim",
    "antoinemadec/FixCursorHold.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  config = function()
    local neotest = require "neotest"

    local neotest_python = require "neotest-python"

    neotest.setup {
      adapters = {
        neotest_python {
          dap = { justMyCode = false },
          runner = "pytest",
        },
      },
      status = { virtual_text = true },
      output = { open_on_run = true },
      quickfix = {
        open = function()
          if require("lazyvim.util").has "trouble.nvim" then
            require("trouble").open { mode = "quickfix", focus = false }
          else
            vim.cmd "copen"
          end
        end,
      },
    }
  end,
}
