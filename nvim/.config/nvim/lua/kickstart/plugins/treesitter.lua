return {
  { -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    -- The main branch does not support lazy-loading.
    lazy = false,
    build = ':TSUpdate',
    config = function()
      local ts = require 'nvim-treesitter'
      ts.install { 'bash', 'c', 'html', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'query', 'vim', 'vimdoc', 'go', 'gomod', 'gowork', 'gosum' }

      local available = {}
      for _, lang in ipairs(ts.get_available()) do
        available[lang] = true
      end

      local function attach(buf, lang)
        if not vim.api.nvim_buf_is_valid(buf) or not vim.treesitter.language.add(lang) then
          return
        end
        vim.treesitter.start(buf, lang)
        -- Ruby's indent rules depend on vim's regex syntax, so keep both for it.
        if lang == 'ruby' then
          vim.bo[buf].syntax = 'on'
        else
          vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
      end

      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('kickstart-treesitter', { clear = true }),
        callback = function(args)
          local buf = args.buf
          local lang = vim.treesitter.language.get_lang(args.match)
          if not lang then
            return
          end
          if vim.treesitter.language.add(lang) then
            attach(buf, lang)
          elseif available[lang] then
            ts.install(lang):await(function()
              vim.schedule(function()
                attach(buf, lang)
              end)
            end)
          end
        end,
      })
    end,
  },
}
-- vim: ts=2 sts=2 sw=2 et
