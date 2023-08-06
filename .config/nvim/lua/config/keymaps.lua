-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
local set = vim.keymap.set

set("n", "<C-u>", "<C-u>zz", { desc = "Go up half a page and center cursor" })
set("n", "<C-d>", "<C-d>zz", { desc = "Go up half a page and center cursor" })
