-- Configure mini.surround to use vim-surround keybindings
return {
  "echasnovski/mini.surround",
  event = "VeryLazy",
  opts = {
    mappings = {
      add = "ys",
      delete = "ds",
      replace = "cs",
      find = "",
      find_left = "",
      highlight = "",
      update_n_lines = "",
      suffix_last = "l",
      suffix_next = "n",
    },
  },
  keys = function()
    return {}
  end,
  config = function(_, opts)
    require("mini.surround").setup(opts)
    -- yss to surround the whole line (like vim-surround)
    vim.keymap.set("n", "yss", "ys_", { remap = true, desc = "Add surrounding to line" })
    -- S in visual mode
    vim.keymap.set("x", "S", [[:<C-u>lua MiniSurround.add('visual')<CR>]], { silent = true, desc = "Add surrounding" })
  end,
}
