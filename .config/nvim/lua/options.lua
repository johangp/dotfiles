require "nvchad.options"

-- add yours here!

local o = vim.o

-- GNU Screen does not reliably render Neovim's 24-bit color output.
-- Keep truecolor elsewhere, but use Screen's 256-color palette inside Screen.
if vim.env.STY or (vim.env.TERM or ""):match "^screen" then
  o.termguicolors = false
end

-- o.cursorlineopt ='both' -- to enable cursorline!
