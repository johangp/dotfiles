require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")
-- map("n", "<leader>g", ":G<cr>")

-- Neotest maps
local neotest = require("neotest")
map("n", "<leader>tt", function() neotest.run.run() end, { desc = "Run nearest test" })
map("n", "<leader>tT", function() neotest.run.run(vim.fn.expand("%")) end, { desc = "Run all tests in file" })
map("n", "<leader>ts", function() neotest.summary.toggle() end, { desc = "Toggle test summary" })
map("n", "<leader>to", function() neotest.output.open({ enter = true }) end, { desc = "Show test output" })
map("n", "<leader>tw", function() neotest.watch.toggle(vim.fn.expand("%")) end, { desc = "Toggle test watch" })
map("n", "<leader>tS", function() neotest.run.stop() end, { desc = "Stop running test" })


-- persistence
map("n", "<leader>qs", function() require("persistence").load() end, { desc = "Restore the sessions from current" })
map("n", "<leader>qS", function() require("persistence").select() end, { desc = "Select session" })
map("n", "<leader>ql", function() require("persistence").load({ last = true }) end, {desc = "Restore the last session" })
map("n", "<leader>qd", function() require("persistence").stop() end, { desc = "Stop current session" })

-- NvimTree
map("n", "<leader>e", "<cmd>NvimTreeToggle<cr>", { desc = "Toggle NvimTree" })

map("n", "<leader>qq", "<cmd>qa!<cr>", { desc = "Force quit Neovim" })
map("n", "<leader>dq", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" })

local diff_quit_group = vim.api.nvim_create_augroup("DiffQuitMapping", { clear = true })
local function set_diff_quit_map(bufnr)
  vim.keymap.set("n", "q", function()
    local ft = vim.bo[bufnr].filetype
    local is_diffview = ft and ft:lower():find("diffview", 1, true) ~= nil

    if is_diffview then
      vim.cmd "DiffviewClose"
      return
    end

    vim.cmd "quit"
  end, {
    buffer = bufnr,
    silent = true,
    desc = "Close current diff window",
  })
  vim.b[bufnr].diff_quit_mapped = true
end

local function clear_diff_quit_map(bufnr)
  if vim.b[bufnr].diff_quit_mapped then
    pcall(vim.keymap.del, "n", "q", { buffer = bufnr })
    vim.b[bufnr].diff_quit_mapped = nil
  end
end

local function should_map_force_quit(bufnr)
  local ft = vim.bo[bufnr].filetype
  local is_diffview = ft and ft:lower():find("diffview", 1, true) ~= nil
  return vim.wo.diff or is_diffview
end

for _, win in ipairs(vim.api.nvim_list_wins()) do
  vim.api.nvim_win_call(win, function()
    local bufnr = vim.api.nvim_get_current_buf()
    if should_map_force_quit(bufnr) then
      set_diff_quit_map(vim.api.nvim_get_current_buf())
    else
      clear_diff_quit_map(bufnr)
    end
  end)
end

vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
  group = diff_quit_group,
  callback = function(args)
    if should_map_force_quit(args.buf) then
      set_diff_quit_map(args.buf)
    else
      clear_diff_quit_map(args.buf)
    end
  end,
})

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")
