return {
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      {
        "sourcegraph/sg.nvim",
        config = true,
      },
    },
    ---@param opts cmp.ConfigSchema
    opts = function(_, opts)
      local cmp = require("cmp")
      opts.sources = cmp.config.sources(vim.list_extend(opts.sources, {
        { name = "cody" },
      }))
    end,
  },
  {
    "sourcegraph/sg.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = true,
  },
}
