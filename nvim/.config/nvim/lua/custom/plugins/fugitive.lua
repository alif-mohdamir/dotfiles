-- return {}
return {
  'tpope/vim-fugitive',
  config = function()
    local set = vim.keymap.set
    set('n', '<leader>gs', vim.cmd.Git, { desc = 'git fugitive' })
    set('n', '<leader>gl', ':Git difftool --name-status --merge-base origin/main <CR>', { desc = 'Git diff list' })
    set('n', '<leader>gd', ':Gvdiff origin/main<CR>', { desc = 'Git diff vertical split' })
    set('n', '<leader>gprom', ':G pull --rebase origin main', { desc = 'Git pull --rebase origin main' })
    set('n', '<leader>gaA', ':G add .<CR>', { desc = '[G]it [a]dd [A]LL modified files' })
    set('n', '<leader>ga', ':G add %<CR>', { desc = '[G]it add current modified file' })
    set('n', '<leader>gc', ':G commit <CR>', { desc = 'Git commit staged files' })
    set('n', '<leader>gcA', ':G commit -a<CR>', { desc = '[G]it [c]ommit and stage [A]LL files' })
    -- vim.keymaps.set('n', '<leader>gs', vim.cmd.Git)
    --
    --     local autocmd = vim.api.nvim_create_autocmd
    --     autocmd('BufWinEnter', {
    --       pattern = '*',
    --       callback = function()
    --         if vim.bo.ft ~= 'fugitive' then
    --           return end
    --
    --         local bufnr = vim.api.nvim_get_current_buf()
    --         local opts = { buffer = bufnr, remap = false }
    --         vim.keymaps.set('n', '<leader>p', function()
    --           vim.cmd.Git 'push'
    --         end, opts)
    --
    --         -- rebase always
    --         vim.keymaps.set('n', '<leader>P', function()
    --           vim.cmd.Git { 'pull', '--rebase' }
    --         end, opts)
    --
    --         -- NOTE: It allows me to easily set the branch i am pushing and any tracking
    --         -- needed if i did not set the branch up correctly
    --         vim.keymaps.set('n', '<leader>t', ':Git push -u origin ', opts)
    --       end,
    --     })
    --
    --     vim.keymaps.set('n', 'gu', '<cmd>diffget //2<CR>')
    --     vim.keymaps.set('n', 'gh', '<cmd>diffget //3<CR>')
  end,
}
