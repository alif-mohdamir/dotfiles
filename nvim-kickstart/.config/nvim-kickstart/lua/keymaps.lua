-- [[ Basic Keymaps ]]
--  See `:help vim.keymap.set()`ap kickstart
local set = vim.keymap.set
-- Set highlight on search, but clear on pressing <Esc> in normal mode
vim.opt.hlsearch = true
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Diagnostic keymaps
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, { desc = 'Go to previous [D]iagnostic message' })
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, { desc = 'Go to next [D]iagnostic message' })
vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Show diagnostic [E]rror messages' })
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

-- Exit terminal mode in the builtin terminal with a shortcut that is a bit easier
-- for people to discover. Otherwise, you normally need to press <C-\><C-n>, which
-- is not what someone will guess without a bit more experience.
--
-- NOTE: This won't work in all terminal emulators/tmux/etc. Try your own mapping
-- or just use <C-\><C-n> to exit terminal mode
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
--
--  See `:help wincmd` for a list of all window commands
vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

set('n', '<C-h>', '<cmd> TmuxNavigateLeft<CR>', { desc = 'tmux window left' })
set('n', '<C-l>', '<cmd> TmuxNavigateRight<CR>', { desc = 'tmux window right' })
set('n', '<C-j>', '<cmd> TmuxNavigateDown<CR>', { desc = 'tmux window down' })
set('n', '<C-k>', '<cmd> TmuxNavigateUp<CR>', { desc = 'tmux window up' })

-- Similar to what I use for tmux with prefix h
set('n', '<leader>wh', ':bprevious<CR>', { desc = 'Previous buffer' })

set('n', '<C-u>', '<C-u>zz', { desc = 'Go up half a page and center cursor' })
set('n', '<C-d>', '<C-d>zz', { desc = 'Go up half a page and center cursor' })

set('v', '<leader>ce', ':CodyExplain<CR>', { desc = 'Explain selected code Cody' })
set('v', '<leader>cA', ':CodyAsk', { desc = 'Ask Cody about selected code' })
set('n', '<leader>ct', ':CodyToggle<CR>', { desc = 'Toggle Cody chat window' })

set('v', '<leader>r', [[y:%s/\<<C-r>"\>/<C-r>"/g<Left><Left>]], { desc = 'Replace selected text in file' })
set('v', '<leader>R', [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]], { desc = 'Replace selected text in selection' })

-- Might be able to use <C-^>?
-- <C-^> opens an empty file vs throwing an error appears to be the main behavior difference
set('n', '<leader>bb', '<cmd>e #<CR>', { desc = 'Switch to last open [b]uffer' })
set('n', '<leader>bp', '<cmd>bprevious<CR>', { desc = 'Switch to [p]revious buffer' })
set('n', '<leader>bn', '<cmd>bnext<CR>', { desc = 'Switch to [n]ext buffer' })
set('n', '<leader>bd', '<cmd>bdelete<CR>', { desc = '[D]elete current buffer' })
set('n', '<leader>E', '<cmd>Explore<CR>', { desc = 'Open Netrw [E]xplorer' })

set('n', '[p', function()
  require('treesitter-context').go_to_context()
end, { desc = 'Go to parent context' })

-- [[ Basic Autocommands ]]
--  See `:help lua-guide-autocommands`

-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.highlight.on_yank()`
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

-- vim: ts=2 sts=2 sw=2 et
