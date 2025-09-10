return {
  { -- Collection of various small independent plugins/modules
    'echasnovski/mini.nvim',
    config = function()
      -- Better Around/Inside textobjects
      --
      -- Examples:
      --  - va)  - [V]isually select [A]round [)]paren
      --  - yinq - [Y]ank [I]nside [N]ext [']quote
      --  - ci'  - [C]hange [I]nside [']quote
      require('mini.ai').setup { n_lines = 500 }

      -- Add/delete/replace surroundings (brackets, quotes, etc.)
      --
      -- - saiw) - [S]urround [A]dd [I]nner [W]ord [)]Paren
      -- - sd'   - [S]urround [D]elete [']quotes
      -- - sr)'  - [S]urround [R]eplace [)] [']
      require('mini.surround').setup()

      -- Simple and easy statusline.
      --  You could remove this setup call if you don't like it,
      --  and try some other statusline plugin
      local statusline = require 'mini.statusline'
      -- set use_icons to true if you have a Nerd Font
      statusline.setup {
        use_icons = vim.g.have_nerd_font,
        -- active = function()
        --   local mode, mode_hl = statusline.section_mode { trunc_width = 120 }
        --   local git = statusline.section_git { trunc_width = 10 }
        --   local diff = statusline.section_diff { trunc_width = 75 }
        --   local diagnostics = statusline.section_diagnostics { trunc_width = 75 }
        --   local lsp = statusline.section_lsp { trunc_width = 75 }
        --   local filename = statusline.section_filename { trunc_width = 140 }
        --   local fileinfo = statusline.section_fileinfo { trunc_width = 120 }
        --   local search = statusline.section_searchcount { trunc_width = 75 }
        --   -- Truncate git branch name to 15 chars
        --   if git ~= '' then
        --     git = git:gsub(' (%S+)', function(branch)
        --       return ' ' .. branch:sub(1, 15)
        --     end)
        --   end
        --
        --   return statusline.combine_groups {
        --     { hl = mode_hl, strings = { mode } },
        --     { hl = 'MiniStatuslineDevinfo', strings = { git, diff, diagnostics, lsp } },
        --     '%<', -- Mark general truncate point
        --     { hl = 'MiniStatuslineFilename', strings = { filename } },
        --     '%=', -- End left alignment
        --     { hl = 'MiniStatuslineFileinfo', strings = { fileinfo } },
        --     { hl = mode_hl, strings = { search } },
        --   }
        -- end,
      }

      -- You can configure sections in the statusline by overriding their
      -- default behavior. For example, here we set the section for
      -- cursor location to LINE:COLUMN
      ---@diagnostic disable-next-line: duplicate-set-field
      statusline.section_location = function()
        return '%2l:%-2v'
      end

      local orig = statusline.section_git
      ---@diagnostic disable-next-line: duplicate-set-field
      statusline.section_git = function(args)
        local s = orig(args)
        if s == '' then
          return s
        end
        -- take the last non-space chunk as the branch; keep the original prefix
        local branch = s:match '(%S+)$'
        if not branch then
          return s
        end
        local prefix = s:sub(1, #s - #branch)

        -- truncate to 15 chars (add … if you like)
        if #branch > 15 then
          branch = branch:sub(1, 15) -- or: branch = branch:sub(1, 15) .. "…"
        end
        return prefix .. branch
      end

      -- ... and there is more!
      --  Check out: https://github.com/echasnovski/mini.nvim
    end,
  },
}
-- vim: ts=2 sts=2 sw=2 et
