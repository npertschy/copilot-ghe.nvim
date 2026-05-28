-- Minimal init for copilot-ghe.nvim tests
-- Requires codecompanion.nvim deps to be available at the path below.
local codecompanion_path = vim.fn.expand("~/.local/share/nvim/lazy/codecompanion.nvim")

-- Add this plugin to runtimepath
vim.cmd([[let &rtp.=','.getcwd()]])

-- Add codecompanion and its deps to runtimepath
vim.cmd("set rtp+=" .. codecompanion_path)
-- Expose codecompanion's test helpers (e.g. tool stubs) via package.path
package.path = codecompanion_path .. "/?.lua;" .. package.path
vim.cmd("set rtp+=" .. codecompanion_path .. "/deps/mini.nvim")
vim.cmd("set rtp+=" .. codecompanion_path .. "/deps/plenary.nvim")
vim.cmd("set rtp+=" .. codecompanion_path .. "/deps/nvim-treesitter")

-- Ensure mini.test is available
require("mini.test").setup()

-- Consistent rendering
vim.o.termguicolors = true
vim.o.background = "dark"
vim.cmd("colorscheme default")

-- Minimal codecompanion config so adapters load
local ok, codecompanion = pcall(require, "codecompanion")
if ok then
  codecompanion.setup({
    adapters = {
      http = {
        opts = {
          allow_insecure = false,
          cache_models_for = 1800,
          proxy = nil,
          show_presets = false,
          show_model_choices = false,
        },
      },
    },
  })
end
