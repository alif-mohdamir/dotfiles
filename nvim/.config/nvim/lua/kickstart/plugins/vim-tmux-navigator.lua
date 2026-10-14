return {
  'christoomey/vim-tmux-navigator',
  init = function()
    -- The title names the directions with splits, so tmux over ssh knows whether C-h/j/k/l belongs to this nvim
    vim.o.title = true
    local function set_title()
      if vim.api.nvim_win_get_config(0).relative ~= '' then
        return
      end
      local dirs = ''
      for _, dir in ipairs { 'h', 'j', 'k', 'l' } do
        if vim.fn.winnr(dir) ~= vim.fn.winnr() then
          dirs = dirs .. dir
        end
      end
      vim.o.titlestring = 'nvimnav-' .. dirs
    end
    vim.api.nvim_create_autocmd({ 'VimEnter', 'WinEnter', 'WinNew', 'WinClosed', 'WinResized', 'TabEnter' }, {
      callback = function()
        vim.schedule(set_title)
      end,
    })
  end,
  cmd = {
    'TmuxNavigateLeft',
    'TmuxNavigateDown',
    'TmuxNavigateUp',
    'TmuxNavigateRight',
    'TmuxNavigatePrevious',
    'TmuxNavigatorProcessList',
  },
  keys = {
    { '<c-h>', '<cmd><C-U>TmuxNavigateLeft<cr>' },
    { '<c-j>', '<cmd><C-U>TmuxNavigateDown<cr>' },
    { '<c-k>', '<cmd><C-U>TmuxNavigateUp<cr>' },
    { '<c-l>', '<cmd><C-U>TmuxNavigateRight<cr>' },
    { '<c-\\>', '<cmd><C-U>TmuxNavigatePrevious<cr>' },
  },
}
