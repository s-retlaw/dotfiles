-- colorscheme.lua - TokyoNight theme configuration

return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "night", -- Darkest variant
    },
  },

  -- Configure LazyVim to use TokyoNight
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "tokyonight",
    },
  },
}
