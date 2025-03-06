require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")
map("n", "<leader>g", ":G<cr>")

-- Neotest maps
local neotest = require("neotest")
map("n", "<leader>tt", function() neotest.run.run() end, { desc = "Run nearest test" })
map("n", "<leader>tT", function() neotest.run.run(vim.fn.expand("%")) end, { desc = "Run all tests in file" })
map("n", "<leader>ts", function() neotest.summary.toggle() end, { desc = "Toggle test summary" })
map("n", "<leader>to", function() neotest.output.open({ enter = true }) end, { desc = "Show test output" })
map("n", "<leader>tw", function() neotest.watch.toggle(vim.fn.expand("%")) end, { desc = "Toggle test watch" })
map("n", "<leader>tS", function() neotest.run.stop() end, { desc = "Stop running test" })

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")
