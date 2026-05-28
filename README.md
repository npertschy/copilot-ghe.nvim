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
  "npertschy/copilot-ghe.nvim",
  dependencies = {
    "olimorris/codecompanion.nvim",
    "nvim-lua/plenary.nvim",
  },
  opts = {
    github_enterprise_url = "ghe.mycompany.com",
  },
},
{
  "olimorris/codecompanion.nvim",
  opts = {
    adapters = {
      http = {
        copilot_ghe = function()
          return require("copilot-ghe").adapter()
        end,
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

`copilot-ghe.nvim` must be listed before `codecompanion.nvim` so that lazy initialises it first.

## Configuration

| Option                  | Type          | Default | Description                                                                                                                                         |
| ----------------------- | ------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `github_enterprise_url` | `string\|nil` | `nil`   | GHE hostname or URL. Both `"ghe.mycompany.com"` and `"https://ghe.mycompany.com"` are accepted. Falls back to `$GH_HOST`, then public `github.com`. |

## How it works

This plugin ships three self-contained files adapted from codecompanion's built-in `copilot` adapter:

| File                                | Purpose                                                                                   |
| ----------------------------------- | ----------------------------------------------------------------------------------------- |
| `lua/copilot-ghe/adapter/token.lua` | OAuth + Copilot token management with GHE endpoint resolution                             |
| `lua/copilot-ghe/adapter/init.lua`  | Adapter definition; requires `token.lua` from this plugin                                 |
| `lua/copilot-ghe/adapter/stats.lua` | Copilot usage stats; `adapter` is passed as a parameter instead of read from module state |

The upstream `get_models.lua` is re-used directly without modification.

### Key differences from the built-in adapter

1. **`resolve_endpoints(adapter)`** — reads `adapter.env.github_enterprise_url` (or `$GH_HOST`) and builds GHE-specific token and stats URLs.
2. **No `M._adapter` module state** — `adapter` is passed as a parameter through the entire token call chain, eliminating a design issue in the original patch where module-level state would break if two adapters with different GHE hosts were used concurrently.
3. **`stats.show(adapter)`** accepts the adapter explicitly rather than reading it from a module-level variable.

## Copilot Stats

The stats window works via the standard codecompanion keymap (default `gs` in the chat buffer). No extra configuration is needed — `show_copilot_stats` is defined on the adapter table, so codecompanion detects it automatically.

## Upstream sync

This plugin contains copies of three upstream files. When codecompanion releases updates to its Copilot adapter, review and merge any changes manually.

| Plugin file                         | Upstream source                                     | Synced at commit |
| ----------------------------------- | --------------------------------------------------- | ---------------- |
| `lua/copilot-ghe/adapter/token.lua` | `lua/codecompanion/adapters/http/copilot/token.lua` | `405bc724`       |
| `lua/copilot-ghe/adapter/init.lua`  | `lua/codecompanion/adapters/http/copilot/init.lua`  | `405bc724`       |
| `lua/copilot-ghe/adapter/stats.lua` | `lua/codecompanion/adapters/http/copilot/stats.lua` | `405bc724`       |

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
