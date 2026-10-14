-- Run by check_nvim.py with isolated config, cache, state, and lockfile.
vim.go.loadplugins = true
vim.opt.rtp:prepend(vim.fn.stdpath("config"))
vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/lazy.nvim")
local lazy = require("lazy")
local setup = lazy.setup
lazy.setup = function(opts)
  opts.checker = { enabled = false }
  opts.install = { missing = false }
  opts.change_detection = { enabled = false }
  table.insert(opts.spec, {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, options) options.ensure_installed = {} end,
  })
  return setup(opts)
end
require("config.lazy")
vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
assert(vim.o.shiftwidth == 2 and vim.o.relativenumber, "shared options missing")
lazy.load({ plugins = { "nvim-treesitter-textobjects", "mini.surround" } })
assert(vim.fn.maparg("af", "o") ~= "", "missing function selection")
assert(vim.fn.maparg("ac", "x") ~= "", "missing class selection")
assert(vim.fn.maparg("<leader>a", "n") ~= "", "missing parameter swap")
assert(vim.fn.maparg("yss", "n") ~= "", "missing surround mapping")
local config = require("lazy.core.config")
assert(config.plugins["nvim-treesitter-textobjects"].branch == "main")
if vim.env.DOTFILES_TEST_OMARCHY == "1" then
  assert(vim.g.colors_name == "habamax", "existing theme was replaced")
else
  assert(vim.g.colors_name:find("tokyonight"), "standalone theme missing")
end
print("PASS: LazyVim startup, theme, shared options, textobjects, surround")
vim.cmd("qa!")
