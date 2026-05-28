# copilot-ghe.nvim

A [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim) adapter that adds GitHub Enterprise (GHE) support for GitHub Copilot.

codecompanion's built-in `copilot` adapter is hardcoded to `github.com`. This plugin registers a self-contained `copilot_ghe` adapter that routes OAuth and Copilot token requests to your GHE instance.

## Requirements

- Neovim 0.10+
- [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- GitHub CLI authenticated against your GHE host:
  ```sh
  gh auth login --hostname ghe.mycompany.com
  ```

## Installation

### lazy.nvim

```lua
{
  "your-username/copilot-ghe.nvim",
  dependencies = {
    "olimorris/codecompanion.nvim",
    "nvim-lua/plenary.nvim",
  },
  opts = {
    github_enterprise_url = "ghe.mycompany.com",
  },
},
```

Then configure codecompanion to use the adapter:

```lua
{
  "olimorris/codecompanion.nvim",
  opts = {
    adapters = {
      http = {
        copilot_ghe = require("copilot-ghe").adapter,
      },
    },
    interactions = {
      chat   = { adapter = "copilot_ghe" },
      inline = { adapter = "copilot_ghe" },
      cmd    = { adapter = "copilot_ghe" },
    },
  },
},
```

> **Note:** `require("copilot-ghe").setup()` must run before `require("codecompanion").setup()`.
> With lazy.nvim, declare `copilot-ghe.nvim` before `codecompanion.nvim` in your plugin list,
> or use `priority` to ensure ordering.

## Configuration

```lua
require("copilot-ghe").setup({
  -- Required: your GHE hostname or URL.
  -- Both "ghe.mycompany.com" and "https://ghe.mycompany.com" are accepted.
  -- Falls back to the GH_HOST environment variable, then public github.com.
  github_enterprise_url = "ghe.mycompany.com",
})
```

## How it works

This plugin ships three self-contained files adapted from codecompanion's built-in `copilot` adapter:

| File | Purpose |
|---|---|
| `lua/copilot-ghe/adapter/token.lua` | OAuth + Copilot token management with GHE endpoint resolution |
| `lua/copilot-ghe/adapter/init.lua` | Adapter definition; requires `token.lua` from this plugin |
| `lua/copilot-ghe/adapter/stats.lua` | Copilot usage stats; `adapter` is passed as a parameter instead of read from module state |

The upstream `get_models.lua` is re-used directly without modification.

### Key differences from the built-in adapter

1. **`resolve_endpoints(adapter)`** — reads `adapter.env.github_enterprise_url` (or `$GH_HOST`) and builds GHE-specific token and stats URLs.
2. **No `M._adapter` module state** — `adapter` is passed as a parameter through the entire token call chain, eliminating a design issue in the original patch where module-level state would break if two adapters with different GHE hosts were used concurrently.
3. **`stats.show(adapter)`** accepts the adapter explicitly rather than reading it from a module-level variable.

## Copilot Stats

The stats window is accessible via:

```lua
require("codecompanion.adapters").resolve("copilot_ghe").show_copilot_stats()
```

Or map it in your config:

```lua
vim.keymap.set("n", "<leader>cs", function()
  require("codecompanion.adapters").resolve("copilot_ghe").show_copilot_stats()
end, { desc = "Copilot GHE stats" })
```

## Upstream sync

This plugin contains copies of three upstream files. When codecompanion releases updates to its Copilot adapter, review and merge any changes manually.

| Plugin file | Upstream source | Synced at commit |
|---|---|---|
| `lua/copilot-ghe/adapter/token.lua` | `lua/codecompanion/adapters/http/copilot/token.lua` | `405bc724` |
| `lua/copilot-ghe/adapter/init.lua` | `lua/codecompanion/adapters/http/copilot/init.lua` | `405bc724` |
| `lua/copilot-ghe/adapter/stats.lua` | `lua/codecompanion/adapters/http/copilot/stats.lua` | `405bc724` |

`lua/codecompanion/adapters/http/copilot/get_models.lua` is **not** copied — it is required directly from codecompanion.

## Development

```sh
# Run tests (requires codecompanion.nvim at ~/.local/share/nvim/lazy/codecompanion.nvim)
make test

# Run a single test file
make test_file FILE=tests/test_copilot_ghe.lua

# Format with StyLua
make format
```
