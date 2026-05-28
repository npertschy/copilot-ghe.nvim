local M = {}

---@class CopilotGHE.Config
---@field github_enterprise_url? string GHE hostname or URL, e.g. "ghe.mycompany.com"
---@field adapter_name? string Key to register under in codecompanion (default: "copilot_ghe")

---@type CopilotGHE.Config
local _config = {
	github_enterprise_url = nil,
	adapter_name = "copilot_ghe",
}

---Return the adapter table with the configured github_enterprise_url baked in.
---Intended for use as a value in codecompanion's adapters.http config.
---@return CodeCompanion.HTTPAdapter
function M.adapter()
	local adapter_def = vim.deepcopy(require("copilot-ghe.adapter"))
	adapter_def.env.github_enterprise_url = _config.github_enterprise_url
	local stats = require("copilot-ghe.adapter.stats")
	adapter_def.show_copilot_stats = function()
		return stats.show(adapter_def)
	end
	return adapter_def
end

---Configure the plugin.
---Call this before (or as part of) your codecompanion setup.
---
---Example (lazy.nvim):
---
---    {
---      "npertschy/copilot-ghe.nvim",
---      dependencies = { "olimorris/codecompanion.nvim" },
---      opts = { github_enterprise_url = "ghe.mycompany.com" },
---    }
---
---Then in your codecompanion setup:
---
---    require("codecompanion").setup({
---      adapters = {
---        http = {
---          copilot_ghe = function()
---            return require("copilot-ghe").adapter()
---          end,
---        },
---      },
---      interactions = {
---        chat   = { adapter = "copilot_ghe" },
---        inline = { adapter = "copilot_ghe" },
---        cmd    = { adapter = "copilot_ghe" },
---      },
---    })
---
---@param opts CopilotGHE.Config
function M.setup(opts)
	opts = opts or {}
	_config = vim.tbl_deep_extend("force", _config, opts)
end

return M
