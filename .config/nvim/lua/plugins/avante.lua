local prefill_edit_window = function(request)
  require("avante.api").edit()
  local code_bufnr = vim.api.nvim_get_current_buf()
  local code_winid = vim.api.nvim_get_current_win()
  if code_bufnr == nil or code_winid == nil then
    return
  end

  -- Split the request string into lines
  local lines = {}
  for line in request:gmatch "([^\n]*)\n?" do
    table.insert(lines, line)
  end

  vim.api.nvim_buf_set_lines(code_bufnr, 0, -1, false, lines)
  -- Optionally set the cursor position to the end of the input
  vim.api.nvim_win_set_cursor(code_winid, { 1, #lines[1] + 1 })
  -- Simulate Ctrl+S keypress to submit
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-s>", true, true, true), "v", true)
end

local avante_grammar_correction = "Correct the text to standard English, but keep any code blocks inside intact."
local avante_keywords = "Extract the main keywords from the following text"
local avante_code_readability_analysis = [[
  You must identify any readability issues in the code snippet.
  Some readability issues to consider:
  - Unclear naming
  - Unclear purpose
  - Redundant or obvious comments
  - Lack of comments
  - Long or complex one liners
  - Too much nesting
  - Long variable names
  - Inconsistent naming and code style.
  - Code repetition
  You may identify additional problems. The user submits a small section of code from a larger file.
  Only list lines with readability issues, in the format <line_num>|<issue and proposed solution>
  If there's no issues with code respond with only: <OK>
]]
local avante_optimize_code = "Optimize the following code"
-- local avante_summarize = 'Summarize the following text'
local avante_explain_code = "Explain the following code"
local avante_complete_code = "Complete the following codes written in " .. vim.bo.filetype
local avante_add_docstring = "Add docstring to the following codes"
local avante_fix_bugs = "Fix the bugs inside the following codes if any"
local avante_add_tests = "Implement tests for the following code"

return {
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    lazy = false,
    version = false, -- Set this to "*" to always pull the latest release version, or set it to false to update to the latest code changes.
    opts = {
      -- add any opts here
      -- for example
      provider = "copilot",
    },
    -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
    build = "make",
    -- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- for windows
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "stevearc/dressing.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      --- The below dependencies are optional,
      "echasnovski/mini.pick", -- for file_selector provider mini.pick
      "nvim-telescope/telescope.nvim", -- for file_selector provider telescope
      "hrsh7th/nvim-cmp", -- autocompletion for avante commands and mentions
      "ibhagwan/fzf-lua", -- for file_selector provider fzf
      "nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
      "zbirenbaum/copilot.lua", -- for providers='copilot'
      {
        -- support for image pasting
        "HakonHarnes/img-clip.nvim",
        event = "VeryLazy",
        opts = {
          -- recommended settings
          default = {
            embed_image_as_base64 = false,
            prompt_for_file_name = false,
            drag_and_drop = {
              insert_mode = true,
            },
            -- required for Windows users
            use_absolute_path = true,
          },
        },
      },
      {
        -- Make sure to set this up properly if you have lazy=true
        "MeanderingProgrammer/render-markdown.nvim",
        opts = {
          file_types = { "markdown", "Avante" },
        },
        ft = { "markdown", "Avante" },
      },
    },
  },

  require("which-key").add {
    { "<leader>a", group = "Avante" }, -- NOTE: add for avante.nvim
    {
      mode = { "v" },
      {
        "<leader>aA",
        function()
          prefill_edit_window(avante_code_readability_analysis)
        end,
        desc = "Code Readability Analysis",
      },
      {
        "<leader>aE",
        function()
          prefill_edit_window(avante_explain_code)
        end,
        desc = "Explain  Code",
      },
      {
        "<leader>aG",
        function()
          prefill_edit_window(avante_grammar_correction)
        end,
        desc = "Grammar Correction",
      },
      {
        "<leader>aK",
        function()
          prefill_edit_window(avante_keywords)
        end,
        desc = "Keywords",
      },
      {
        "<leader>aO",
        function()
          prefill_edit_window(avante_optimize_code)
        end,
        desc = "Optimize Code(edit)",
      },
      {
        "<leader>aC",
        function()
          prefill_edit_window(avante_complete_code)
        end,
        desc = "Complete Code(edit)",
      },
      {
        "<leader>aD",
        function()
          prefill_edit_window(avante_add_docstring)
        end,
        desc = "Docstring(edit)",
      },
      {
        "<leader>at",
        function()
          prefill_edit_window(avante_fix_bugs)
        end,
        desc = "Fix Bugs(edit)",
      },
      {
        "<leader>aU",
        function()
          prefill_edit_window(avante_add_tests)
        end,
        desc = "Add Tests(edit)",
      },
    },
  },
}
