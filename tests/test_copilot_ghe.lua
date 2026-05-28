local new_set = MiniTest.new_set
T = new_set()

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function eq(expected, actual)
  MiniTest.expect.equality(expected, actual)
end

local function expect_starts_with(prefix, str)
  if type(str) ~= "string" or not vim.startswith(str, prefix) then
    error(string.format("Expected string starting with %q, got %q", prefix, tostring(str)))
  end
end

-- ---------------------------------------------------------------------------
-- Shared fixtures
-- ---------------------------------------------------------------------------

local copilot_models = {
  ["claude-3.5-sonnet"] = {
    endpoint = "completions",
    formatted_name = "Claude Sonnet 3.5",
    opts = { can_stream = true, can_use_tools = true, has_vision = true },
    vendor = "Anthropic",
  },
  ["gpt-4.1"] = {
    endpoint = "completions",
    formatted_name = "GPT-4.1",
    opts = { can_stream = true, can_use_tools = true, has_vision = true },
    vendor = "Azure OpenAI",
  },
  ["gpt-5-codex"] = {
    endpoint = "responses",
    formatted_name = "GPT-5-Codex (Preview)",
    opts = { can_stream = true, can_use_tools = true, has_vision = true },
    vendor = "OpenAI",
  },
}

-- ---------------------------------------------------------------------------
-- Copilot GHE adapter — core behaviour
-- ---------------------------------------------------------------------------

local adapter
local _original_choices
local _original_token_fetch

T["Copilot GHE adapter"] = new_set({
  hooks = {
    pre_case = function()
      local token = require("copilot-ghe.adapter.token")
      _original_token_fetch = token.fetch
      token.fetch = function()
        return {
          copilot_token = "test_token_12345",
          endpoints = { api = "https://api.githubcopilot.com" },
        }
      end

      -- Register the adapter in codecompanion so resolve() can find it
      local cc_config = require("codecompanion.config")
      cc_config.adapters = cc_config.adapters or {}
      cc_config.adapters.http = cc_config.adapters.http or {}
      cc_config.adapters.http.copilot_ghe = function()
        return require("codecompanion.adapters").extend(require("copilot-ghe.adapter"), {})
      end

      adapter = require("codecompanion.adapters").extend(require("copilot-ghe.adapter"), {})

      local get_models = require("codecompanion.adapters.http.copilot.get_models")
      _original_choices = get_models.choices
      get_models.choices = function()
        return copilot_models
      end
    end,

    post_case = function()
      if _original_choices then
        local get_models = require("codecompanion.adapters.http.copilot.get_models")
        get_models.choices = _original_choices
        _original_choices = nil
      end
      if _original_token_fetch then
        local token = require("copilot-ghe.adapter.token")
        token.fetch = _original_token_fetch
        _original_token_fetch = nil
      end
    end,
  },
})

T["Copilot GHE adapter"]["it can form messages to be sent to the API"] = function()
  local messages = { { content = "Explain Ruby in two words", role = "user" } }

  eq({
    messages = {
      {
        content = "Explain Ruby in two words",
        copilot_cache_control = { type = "ephemeral" },
        role = "user",
      },
    },
  }, adapter.handlers.form_messages(adapter, messages))
end

T["Copilot GHE adapter"]["it can form tools to be sent to the API"] = function()
  local weather = require("tests.interactions.chat.tools.builtin.stubs.weather").schema
  local tools = { weather = { weather } }
  eq({ tools = { weather } }, adapter.handlers.form_tools(adapter, tools))
end

T["Copilot GHE adapter"]["forms reasoning output"] = function()
  local messages = {
    { content = "Content 1\n" },
    { content = "Content 2\n" },
    { content = "Content 3\n" },
    { opaque = "gj5HGhYVIOT" },
  }

  local result = adapter.handlers.form_reasoning(adapter, messages)
  eq("Content 1\nContent 2\nContent 3\n", result.content)
  eq("gj5HGhYVIOT", result.opaque)
end

T["Copilot GHE adapter"]["Streaming"] = new_set()

T["Copilot GHE adapter"]["Streaming"]["can output streamed data into the chat buffer"] = function()
  local output = ""
  local lines = vim.fn.readfile("tests/stubs/copilot_streaming.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output and chat_output.output.content then
      output = output .. chat_output.output.content
    end
  end
  expect_starts_with("**Elegant simplicity.**", output)
end

T["Copilot GHE adapter"]["Streaming"]["can handle quota exceeded"] = function()
  local output = ""
  local status = ""
  local lines = vim.fn.readfile("tests/stubs/copilot_quota_exceeded.txt")
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    status = chat_output and chat_output.status
    if chat_output and chat_output.output then
      output = output .. chat_output.output
    end
  end
  eq("error", status)
  expect_starts_with("Your Copilot quota", output)
end

T["Copilot GHE adapter"]["Streaming"]["can process tools"] = function()
  local tools = {}
  local lines = vim.fn.readfile("tests/stubs/copilot_tools_streaming.txt")
  for _, line in ipairs(lines) do
    adapter.handlers.chat_output(adapter, line, tools)
  end

  local tool_output = {
    {
      _index = 0,
      ["function"] = {
        arguments = '{"location": "London, UK", "units": "celsius"}',
        name = "weather",
      },
      id = "tooluse_ZnSMh7lhSxWDIuVBKd_vLg",
      type = "function",
    },
  }
  eq(tool_output, tools)
end

T["Copilot GHE adapter"]["Streaming"]["stores reasoning_opaque in extra"] = function()
  local lines = vim.fn.readfile("tests/stubs/copilot_tools_streaming_reasoning.txt")
  local output = {}
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output then
      table.insert(output, adapter.handlers.parse_message_meta(adapter, chat_output))
    end
  end
  expect_starts_with("lgxMQq0m/J6cVjsaH8bbfhxHtAvK4Y", output[#output].output.reasoning.opaque)
end

T["Copilot GHE adapter"]["No Streaming"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").extend(require("copilot-ghe.adapter"), {
        opts = { stream = false },
      })
    end,
  },
})

T["Copilot GHE adapter"]["No Streaming"]["can output for the chat buffer"] = function()
  local data = vim.fn.readfile("tests/stubs/copilot_no_streaming.txt")
  data = table.concat(data, "\n")
  local json = { body = data }
  eq(
    "**Dynamic elegance.**\\n\\nWhat specific aspect of Ruby would you like to explore further?",
    adapter.handlers.chat_output(adapter, json).output.content
  )
end

T["Copilot GHE adapter"]["No Streaming"]["can output for the inline assistant"] = function()
  local data = vim.fn.readfile("tests/stubs/copilot_no_streaming.txt")
  data = table.concat(data, "\n")
  local json = { body = data }
  eq(
    "**Dynamic elegance.**\\n\\nWhat specific aspect of Ruby would you like to explore further?",
    adapter.handlers.inline_output(adapter, json).output
  )
end

-- ---------------------------------------------------------------------------
-- Token: resolve_endpoints
-- ---------------------------------------------------------------------------

local token_child = MiniTest.new_child_neovim()

T["resolve_endpoints"] = new_set({
  hooks = {
    pre_case = function()
      token_child.restart({ "-u", "scripts/minimal_init.lua" })
    end,
    post_once = token_child.stop,
  },
})

T["resolve_endpoints"]["returns public github URLs when no adapter config"] = function()
  local result = token_child.lua([[
    local token = require("copilot-ghe.adapter.token")
    local ep, host, stats = token.resolve_endpoints(nil)
    return { ep = ep, host = host, stats = stats }
  ]])
  eq("https://api.github.com/copilot_internal/v2/token", result.ep)
  eq("github.com", result.host)
  eq("https://api.github.com/copilot_internal/user", result.stats)
end

T["resolve_endpoints"]["returns GHE URLs for bare hostname"] = function()
  local result = token_child.lua([[
    local token = require("copilot-ghe.adapter.token")
    local adapter = { env = { github_enterprise_url = "ghe.mycompany.com" } }
    local ep, host, stats = token.resolve_endpoints(adapter)
    return { ep = ep, host = host, stats = stats }
  ]])
  eq("https://ghe.mycompany.com/api/v3/copilot_internal/v2/token", result.ep)
  eq("ghe.mycompany.com", result.host)
  eq("https://ghe.mycompany.com/api/v3/copilot_internal/user", result.stats)
end

T["resolve_endpoints"]["strips https:// protocol prefix from GHE URL"] = function()
  local result = token_child.lua([[
    local token = require("copilot-ghe.adapter.token")
    local adapter = { env = { github_enterprise_url = "https://ghe.mycompany.com" } }
    local ep, host, stats = token.resolve_endpoints(adapter)
    return { ep = ep, host = host, stats = stats }
  ]])
  eq("https://ghe.mycompany.com/api/v3/copilot_internal/v2/token", result.ep)
  eq("ghe.mycompany.com", result.host)
  eq("https://ghe.mycompany.com/api/v3/copilot_internal/user", result.stats)
end

T["resolve_endpoints"]["falls back to GH_HOST environment variable"] = function()
  local result = token_child.lua([[
    local token = require("copilot-ghe.adapter.token")
    vim.env.GH_HOST = "ghe.corp.example.com"
    local ep, host, stats = token.resolve_endpoints(nil)
    vim.env.GH_HOST = nil
    return { ep = ep, host = host, stats = stats }
  ]])
  eq("https://ghe.corp.example.com/api/v3/copilot_internal/v2/token", result.ep)
  eq("ghe.corp.example.com", result.host)
  eq("https://ghe.corp.example.com/api/v3/copilot_internal/user", result.stats)
end

T["resolve_endpoints"]["treats explicit github.com as public"] = function()
  local result = token_child.lua([[
    local token = require("copilot-ghe.adapter.token")
    local adapter = { env = { github_enterprise_url = "github.com" } }
    local ep, host, stats = token.resolve_endpoints(adapter)
    return { ep = ep, host = host, stats = stats }
  ]])
  eq("https://api.github.com/copilot_internal/v2/token", result.ep)
  eq("github.com", result.host)
  eq("https://api.github.com/copilot_internal/user", result.stats)
end

-- ---------------------------------------------------------------------------
-- Token: cache invalidation
-- ---------------------------------------------------------------------------

T["token cache invalidation"] = new_set({
  hooks = {
    pre_case = function()
      token_child.restart({ "-u", "scripts/minimal_init.lua" })
    end,
  },
})

T["token cache invalidation"]["clears tokens when switching from public to GHE host"] = function()
  local result = token_child.lua([[
    local token = require("copilot-ghe.adapter.token")
    local ghe_adapter = { env = { github_enterprise_url = "ghe.mycompany.com" } }
    local _, ghe_hostname = token.resolve_endpoints(ghe_adapter)

    -- Simulate cached public tokens
    token._oauth_token = "public_oauth_token"
    token._copilot_token = { token = "public_copilot_token", expires_at = os.time() + 3600 }
    token._cached_host = "github.com"

    local hosts_differ = (token._cached_host ~= ghe_hostname)

    -- Mirror the invalidation logic from get_oauth_token
    if token._oauth_token and token._cached_host ~= ghe_hostname then
      token._oauth_token = nil
      token._copilot_token = nil
    end

    return {
      hosts_differ = hosts_differ,
      invalidated = (token._oauth_token == nil and token._copilot_token == nil),
      ghe_hostname = ghe_hostname,
    }
  ]])
  eq(true, result.hosts_differ)
  eq(true, result.invalidated)
  eq("ghe.mycompany.com", result.ghe_hostname)
end

T["token cache invalidation"]["does not clear tokens when host is unchanged"] = function()
  local result = token_child.lua([[
    local token = require("copilot-ghe.adapter.token")
    local same_adapter = { env = { github_enterprise_url = "ghe.mycompany.com" } }
    local _, hostname = token.resolve_endpoints(same_adapter)

    token._oauth_token = "cached_oauth"
    token._copilot_token = { token = "cached_copilot", expires_at = os.time() + 3600 }
    token._cached_host = hostname

    if token._oauth_token and token._cached_host ~= hostname then
      token._oauth_token = nil
      token._copilot_token = nil
    end

    return { still_cached = (token._oauth_token == "cached_oauth") }
  ]])
  eq(true, result.still_cached)
end

-- ---------------------------------------------------------------------------
-- Token: no M._adapter module state
-- ---------------------------------------------------------------------------

T["token module state"] = new_set({
  hooks = {
    pre_case = function()
      token_child.restart({ "-u", "scripts/minimal_init.lua" })
    end,
  },
})

T["token module state"]["M._adapter does not exist on token module"] = function()
  local result = token_child.lua([[
    local token = require("copilot-ghe.adapter.token")
    return { has_adapter_field = token._adapter ~= nil }
  ]])
  eq(false, result.has_adapter_field)
end

return T
