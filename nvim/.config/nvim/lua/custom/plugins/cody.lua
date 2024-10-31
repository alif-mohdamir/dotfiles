--  Optionally, you can also install nvim-telescope/telescope.nvim to use some search functionality.
return {
  {
    'sourcegraph/sg.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-telescope/telescope.nvim',
    },
    lazy = false,
    opts = {},
    config = function()
      local output = require('op').get_secret('Sourcegraph Access Token', 'token,endpoint')
      if not output then
        error 'Failed to get Sourcegraph token from 1Password'
      end
      local secrets = vim.split(output, ',')
      local token = secrets[1]
      local endpoint = secrets[2]
      vim.env.SRC_ENDPOINT = endpoint
      vim.env.SRC_ACCESS_TOKEN = token
      require('sg').setup {
        enable_cody = false,
      }
    end,
  },
}
