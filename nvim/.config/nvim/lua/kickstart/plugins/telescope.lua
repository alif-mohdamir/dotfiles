--NOTE: Plugins can specify dependencies.
--
-- The dependencies are proper plugin specifications as well - anything
-- you do for a plugin at the top level, you can do for a dependency.
--
-- Use the `dependencies` key to specify the dependencies of a particular plugin

return {
  { -- Fuzzy Finder (files, lsp, etc)
    'nvim-telescope/telescope.nvim',
    event = 'VimEnter',
    branch = '0.1.x',
    dependencies = {
      'nvim-lua/plenary.nvim',
      { -- If encountering errors, see telescope-fzf-native README for installation instructions
        'nvim-telescope/telescope-fzf-native.nvim',
        -- `build` is used to run some command when the plugin is installed/updated.
        -- This is only run then, not every time Neovim starts up.
        build = 'make',

        -- `cond` is a condition used to determine whether this plugin should be
        -- installed and loaded.
        cond = function()
          return vim.fn.executable 'make' == 1
        end,
      },
      { 'nvim-telescope/telescope-ui-select.nvim' },
      {
        'mollerhoj/telescope-recent-files.nvim',
        config = function()
          require('telescope').load_extension 'recent-files'
        end,
      },
      {
        'mrloop/telescope-git-branch.nvim',
        config = function()
          require('telescope').load_extension 'git_branch'
        end,
      },
      -- Useful for getting pretty icons, but requires a Nerd Font.
      { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
    },
    config = function()
      -- Telescope is a fuzzy finder that comes with a lot of different things that
      -- it can fuzzy find! It's more than just a "file finder", it can search
      -- many different aspects of Neovim, your workspace, LSP, and more!
      --
      -- The easiest way to use Telescope, is to start by doing something like:
      --  :Telescope help_tags
      --
      -- After running this command, a window will open up and you're able to
      -- type in the prompt window. You'll see a list of `help_tags` options and
      -- a corresponding preview of the help.
      --
      -- Two important keymaps to use while in Telescope are:
      --  - Insert mode: <c-/>
      --  - Normal mode: ?
      --
      -- This opens a window that shows you all of the keymaps for the current
      -- Telescope picker. This is really useful to discover what Telescope can
      -- do as well as how to actually do it!

      -- [[ Configure Telescope ]]
      -- See `:help telescope` and `:help telescope.setup()`
      require('telescope').setup {
        -- You can put your default mappings / updates / etc. in here
        --  All the info you're looking for is in `:help telescope.setup()`
        --
        -- defaults = {
        --   mappings = {
        --     i = { ['<c-enter>'] = 'to_fuzzy_refine' },
        --   },
        -- },
        -- pickers = {}
        extensions = {
          ['ui-select'] = {
            require('telescope.themes').get_dropdown(),
          },
        },
      }

      local actions = require 'telescope.actions'
      local finders = require 'telescope.finders'
      local make_entry = require 'telescope.make_entry'
      local pickers = require 'telescope.pickers'
      local sorters = require 'telescope.sorters'
      local utils = require 'telescope.utils'
      local conf = require('telescope.config').values
      local Path = require 'plenary.path'

      -- local get_qfix_filelist = function(cwd)
      --   local filelist = {}
      --   for _, v in pairs(vim.fn.getqflist()) do
      --     local file = vim.api.nvim_buf_get_name(v.bufnr)
      --     table.insert(filelist, Path:new(file):make_relative(cwd))
      --   end
      --   utils.notify('filelist', {
      --     msg = string.format(
      --       "'ripgrep', or similar alternative, is a required dependency for the %s picker. "
      --         .. 'Visit https://github.com/BurntSushi/ripgrep#installation for installation instructions.',
      --       filelist
      --     ),
      --     level = 'ERROR',
      --   })
      --   return filelist
      -- end
      --
      -- local opts_contain_invert = function(args)
      --   local invert = false
      --   local files_with_matches = false
      --
      --   for _, v in ipairs(args) do
      --     if v == '--invert-match' then
      --       invert = true
      --     elseif v == '--files-with-matches' or v == '--files-without-match' then
      --       files_with_matches = true
      --     end
      --
      --     if #v >= 2 and v:sub(1, 1) == '-' and v:sub(2, 2) ~= '-' then
      --       local non_option = false
      --       for i = 2, #v do
      --         local vi = v:sub(i, i)
      --         if vi == '=' then -- ignore option -g=xxx
      --           break
      --         elseif vi == 'g' or vi == 'f' or vi == 'm' or vi == 'e' or vi == 'r' or vi == 't' or vi == 'T' then
      --           non_option = true
      --         elseif non_option == false and vi == 'v' then
      --           invert = true
      --         elseif non_option == false and vi == 'l' then
      --           files_with_matches = true
      --         end
      --       end
      --     end
      --   end
      --   return invert, files_with_matches
      -- end
      -- local has_rg_program = function(picker_name, program)
      --   if vim.fn.executable(program) == 1 then
      --     return true
      --   end
      --
      --   utils.notify(picker_name, {
      --     msg = string.format(
      --       "'ripgrep', or similar alternative, is a required dependency for the %s picker. "
      --         .. 'Visit https://github.com/BurntSushi/ripgrep#installation for installation instructions.',
      --       picker_name
      --     ),
      --     level = 'ERROR',
      --   })
      --   return false
      -- end
      --
      -- local grep_qfixlist = function(opts)
      --   local vimgrep_arguments = opts.vimgrep_arguments or conf.vimgrep_arguments
      --   if not has_rg_program('live_grep', vimgrep_arguments[1]) then
      --     return
      --   end
      --   local search_dirs = opts.search_dirs
      --   local grep_open_files = opts.grep_open_files
      --   opts.cwd = opts.cwd and utils.path_expand(opts.cwd) or vim.loop.cwd()
      --
      --   local filelist = get_qfix_filelist(opts.cwd)
      --   if search_dirs then
      --     for i, path in ipairs(search_dirs) do
      --       search_dirs[i] = utils.path_expand(path)
      --     end
      --   end
      --
      --   local additional_args = {}
      --   if opts.additional_args ~= nil then
      --     if type(opts.additional_args) == 'function' then
      --       additional_args = opts.additional_args(opts)
      --     elseif type(opts.additional_args) == 'table' then
      --       additional_args = opts.additional_args
      --     end
      --   end
      --
      --   if opts.type_filter then
      --     additional_args[#additional_args + 1] = '--type=' .. opts.type_filter
      --   end
      --
      --   if type(opts.glob_pattern) == 'string' then
      --     additional_args[#additional_args + 1] = '--glob=' .. opts.glob_pattern
      --   elseif type(opts.glob_pattern) == 'table' then
      --     for i = 1, #opts.glob_pattern do
      --       additional_args[#additional_args + 1] = '--glob=' .. opts.glob_pattern[i]
      --     end
      --   end
      --
      --   if opts.file_encoding then
      --     additional_args[#additional_args + 1] = '--encoding=' .. opts.file_encoding
      --   end
      --
      --   local args = utils.flatten { vimgrep_arguments, additional_args }
      --   opts.__inverted, opts.__matches = opts_contain_invert(args)
      --
      --   local live_grepper = finders.new_job(function(prompt)
      --     if not prompt or prompt == '' then
      --       return nil
      --     end
      --
      --     local search_list = filelist
      --
      --     return utils.flatten { args, '--', prompt, search_list }
      --   end, opts.entry_maker or make_entry.gen_from_vimgrep(opts), opts.max_results, opts.cwd)
      --   pickers.new(opts, {
      --     prompt_title = 'Live Grep Quick Fix List',
      --     finder = live_grepper,
      --     previewer = conf.grep_previewer(opts),
      --     sorter = sorters.highlighter_only(opts),
      --     attach_mappings = function(_, map)
      --       map('i', '<c-space>', actions.to_fuzzy_refine)
      --       return true
      --     end,
      --   })
      -- end

      -- Enable Telescope extensions if they are installed
      pcall(require('telescope').load_extension, 'fzf')
      pcall(require('telescope').load_extension, 'ui-select')

      -- See `:help telescope.builtin`
      local builtin = require 'telescope.builtin'

      vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
      vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
      vim.keymap.set('n', '<leader>sF', builtin.find_files, { desc = '[S]earch [F]iles' })
      vim.keymap.set('n', '<leader>sf', '<cmd>Telescope find_files hidden=true<cr>', { desc = '[S]earch Hidden [F]iles' })
      vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
      vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
      vim.keymap.set('n', '<leader>sG', builtin.live_grep, { desc = '[S]earch by [G]rep' })
      vim.keymap.set('n', '<leader>sB', function()
        builtin.find_files { cwd = utils.buffer_dir() }
      end, { desc = '[S]earch Files in [B]uffer Directory' })
      vim.keymap.set(
        'n',
        '<leader>sg',
        '<cmd>Telescope live_grep vimgrep_arguments=rg,--color=never,--no-heading,--no-heading,--line-number,--column,--smart-case,--hidden,--no-ignore<cr>',
        { desc = '[S]earch Hidden by [G]rep' }
      )
      -- vim.keymap.set('n', '<leader>sq', function()
      --   grep_qfixlist {
      --     vimgrep_arguments = { 'rg', '--color=never', '--no-heading', '--no-heading', '--line-number', '--column', '--smart-case', '--hidden', '--no-ignore' },
      --   }
      -- end, { desc = '[S]earch [Q]uickfix List With Grep' })
      vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
      vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
      vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
      vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })
      vim.keymap.set('n', '<leader>sb', '<cmd>Telescope git_branch<CR>', { desc = '[S]earch Git [B]ranch' })

      -- Slightly advanced example of overriding default behavior and theme
      vim.keymap.set('n', '<leader>/', function()
        -- You can pass additional configuration to Telescope to change the theme, layout, etc.
        builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
          winblend = 10,
          previewer = false,
        })
      end, { desc = '[/] Fuzzily search in current buffer' })

      -- It's also possible to pass additional configuration options.
      --  See `:help telescope.builtin.live_grep()` for information about particular keys
      vim.keymap.set('n', '<leader>s/', function()
        builtin.live_grep {
          grep_open_files = true,
          prompt_title = 'Live Grep in Open Files',
        }
      end, { desc = '[S]earch [/] in Open Files' })

      -- Shortcut for searching your Neovim configuration files
      vim.keymap.set('n', '<leader>sn', function()
        builtin.find_files { cwd = vim.fn.stdpath 'config', follow = true }
      end, { desc = '[S]earch [N]eovim files' })
    end,
  },
}
-- vim: ts=2 sts=2 sw=2 et
