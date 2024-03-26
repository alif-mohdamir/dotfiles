-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
local set = vim.keymap.set

set("n", "<C-h>", "<cmd> TmuxNavigateLeft<CR>", { desc = "tmux window left" })
set("n", "<C-l>", "<cmd> TmuxNavigateRight<CR>", { desc = "tmux window right" })
set("n", "<C-j>", "<cmd> TmuxNavigateDown<CR>", { desc = "tmux window down" })
set("n", "<C-k>", "<cmd> TmuxNavigateUp<CR>", { desc = "tmux window up" })

set("n", "<leader>wh", "<C-w>h", { desc = "vim window left" })
set("n", "<leader>wl", "<C-w>l", { desc = "vim window right" })
set("n", "<leader>wj", "<C-w>j", { desc = "vim window down" })
set("n", "<leader>wk", "<C-w>k", { desc = "vim window up" })

set("n", "<C-u>", "<C-u>zz", { desc = "Go up half a page and center cursor" })
set("n", "<C-d>", "<C-d>zz", { desc = "Go up half a page and center cursor" })
set("v", "<leader>ce", ":CodyExplain<CR>", { desc = "Explain selected code Cody" })

set("v", "<leader>cA", ":CodyAsk", { desc = "Ask Cody about selected code" })
set("n", "<leader>ct", ":CodyToggle<CR>", { desc = "Toggle Cody chat window" })

-- set("v", "<leader>ce", "<cmd> CodyExplain<CR>", { desc = "Explain selected code" })
-- [[:<C-u>execute "CodyExplain " . join(getline("'<","'>"), "\n")<CR>]]
-- :<C-u>execute "YourPackageCommand " . getline("'<","'>")<CR>

set(
  "v",
  "<leader>r",
  [[y:%s/\<<C-r><C-w>\>/<C-r><C-w>/g<Left><Left><Left>]],
  { desc = "Replace selected text in file" }
)

set("n", "[c", function()
  require("treesitter-context").go_to_context()
end, { desc = "Go to parent context" })
