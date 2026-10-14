-- LazyVim supplies function/class/parameter motions. Add selections and swaps
-- using the textobjects main-branch API, rather than the old Treesitter module.
local keys = {}
for key, query in pairs({
  af = "@function.outer", ["if"] = "@function.inner",
  ac = "@class.outer", ic = "@class.inner",
  aa = "@parameter.outer", ia = "@parameter.inner",
}) do
  local capture = query
  keys[#keys + 1] = {
    key,
    function()
      require("nvim-treesitter-textobjects.select").select_textobject(capture, "textobjects")
    end,
    mode = { "x", "o" },
    desc = "Select " .. capture,
  }
end
keys[#keys + 1] = {
  "<leader>a",
  function() require("nvim-treesitter-textobjects.swap").swap_next("@parameter.inner") end,
  desc = "Swap next parameter",
}
keys[#keys + 1] = {
  "<leader>A",
  function() require("nvim-treesitter-textobjects.swap").swap_previous("@parameter.inner") end,
  desc = "Swap previous parameter",
}
return {
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    opts = { select = { lookahead = true } },
    keys = keys,
  },
}
