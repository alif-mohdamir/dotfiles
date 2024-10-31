return {
  'mrjones2014/op.nvim',
  lazy = false,
  build = 'make install',
  -- `cond` is a condition used to determine whether this plugin should be
  -- installed and loaded.
  -- cond = function()
  --   return vim.fn.executable 'make' == 1
  -- end,
  cmd = {
    'OpSignin',
    'OpSignout',
    'OpWhoami',
    'OpCreate',
    'OpView',
    'OpEdit',
    'OpOpen',
    'OpInsert',
    'OpNote',
    'OpSidebar',
    'OpAnalyzeBuffer',
  },
  opts = {
    sidebar = {
      side = 'left',
    },
    statusline_fmt = function(account)
      if not account or #account == 0 then
        return ' 1P: Signed Out'
      end

      return string.format(' 1P: %s', account)
    end,
  },
}
