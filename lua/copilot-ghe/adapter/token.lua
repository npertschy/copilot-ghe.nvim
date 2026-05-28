local Curl = require("plenary.curl")

local config = require("codecompanion.config")
local files = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

local M = {}

-- Reference: https://github.com/yetone/avante.nvim/blob/22418bff8bcac4377ebf975cd48f716823867979/lua/avante/providers/copilot.lua#L5-L26
---@class CopilotToken
---@field annotations_enabled boolean
---@field chat_enabled boolean
---@field chat_jetbrains_enabled boolean
---@field code_quote_enabled boolean
---@field codesearch boolean
---@field copilotignore_enabled boolean
---@field endpoints { api: string, ["origin-tracker"]: string, proxy: string, telemetry: string }
---@field expires_at number
---@field individual boolean
---@field nes_enabled boolean
---@field prompt_8k boolean
---@field public_suggestions string
---@field refresh_in number
---@field sku string
---@field snippy_load_test_enabled boolean
---@field telemetry string
---@field token string -- The actual token we use in our requests
---@field tracking_id string
---@field vsc_electron_fetcher boolean
---@field xcode boolean
---@field xcode_chat boolean

---@alias CopilotOAuthToken string|nil
M._oauth_token = nil

---@type CopilotToken|nil
M._copilot_token = nil

---@type string|nil The hostname used when caching the current oauth/copilot tokens
M._cached_host = nil

-- Lock to prevent concurrent token requests
local _token_fetch_in_progress = false
local _token_wait_timeout = 5000 -- ms
local _token_wait_interval = 50 -- ms

---Resolve the Copilot token endpoint URL from the adapter config, environment, or default
---@param adapter? CodeCompanion.HTTPAdapter
---@return string token_endpoint, string auth_hostname, string stats_endpoint
function M.resolve_endpoints(adapter)
  local enterprise_url = adapter and adapter.env and adapter.env.github_enterprise_url
  local host = enterprise_url or vim.env.GH_HOST

  if not host or host == "github.com" then
    return "https://api.github.com/copilot_internal/v2/token",
      "github.com",
      "https://api.github.com/copilot_internal/user"
  end

  -- Strip any trailing slash and protocol so we can build clean URLs
  local hostname = host:gsub("^https?://", ""):gsub("/+$", "")
  local token_endpoint = string.format("https://%s/api/v3/copilot_internal/v2/token", hostname)
  local stats_endpoint = string.format("https://%s/api/v3/copilot_internal/user", hostname)

  return token_endpoint, hostname, stats_endpoint
end

---Finds the configuration path
---@return string|nil
local function find_config_path()
  if os.getenv("CODECOMPANION_TOKEN_PATH") then
    return os.getenv("CODECOMPANION_TOKEN_PATH")
  end

  local path = vim.fs.normalize("$XDG_CONFIG_HOME")

  if path and vim.fn.isdirectory(path) > 0 then
    return path
  elseif vim.fn.has("win32") > 0 then
    path = vim.fs.normalize("~/AppData/Local")
    if vim.fn.isdirectory(path) > 0 then
      return path
    end
  else
    path = vim.fs.normalize("~/.config")
    if vim.fn.isdirectory(path) > 0 then
      return path
    end
  end
end

---The function first attempts to load the token from the environment variables,
---specifically for GitHub Codespaces. If not found, it then attempts to load
---the token from configuration files located in the user's configuration path.
---@param adapter? CodeCompanion.HTTPAdapter
---@return CopilotOAuthToken
local function get_oauth_token(adapter)
  local _, auth_hostname = M.resolve_endpoints(adapter)

  -- Invalidate cached token if the target host has changed
  if M._oauth_token and M._cached_host ~= auth_hostname then
    M._oauth_token = nil
    M._copilot_token = nil
  end

  if M._oauth_token then
    return M._oauth_token
  end

  local token = os.getenv("GITHUB_TOKEN")
  local codespaces = os.getenv("CODESPACES")
  if token and codespaces then
    return token
  end

  local config_path = find_config_path()
  if not config_path then
    return nil
  end

  local file_paths = {
    config_path .. "/github-copilot/hosts.json",
    config_path .. "/github-copilot/apps.json",
  }

  for _, file_path in ipairs(file_paths) do
    if vim.uv.fs_stat(file_path) then
      local ok, userdata = pcall(files.read, file_path)
      if not ok then
        log:error("Copilot GHE Adapter: Could not read token from %s: %s", file_path, userdata)
        return nil
      end

      if vim.islist(userdata) then
        userdata = table.concat(userdata, " ")
      end

      userdata = vim.json.decode(userdata)
      for key, value in pairs(userdata) do
        if string.find(key, auth_hostname, 1, true) then
          return value.oauth_token
        end
      end
    end
  end

  return nil
end

---Get a GitHub Copilot token using the OAuth token
---@param adapter? CodeCompanion.HTTPAdapter
---@return CopilotToken|nil
local function get_copilot_token(adapter)
  if M._copilot_token and M._copilot_token.expires_at and M._copilot_token.expires_at > os.time() then
    log:trace("Copilot GHE Adapter: Reusing GitHub Copilot token")
    return M._copilot_token
  end

  -- If another fetch is in progress, wait and prevent multiple requests
  if _token_fetch_in_progress then
    local ok = vim.wait(_token_wait_timeout, function()
      return M._copilot_token and M._copilot_token.expires_at and M._copilot_token.expires_at > os.time()
    end, _token_wait_interval)
    if ok then
      log:trace("Copilot GHE Adapter: Using token fetched by concurrent request")
      return M._copilot_token
    end
  end

  _token_fetch_in_progress = true
  log:trace("Authorizing GitHub Copilot GHE token")

  local token_endpoint, _ = M.resolve_endpoints(adapter)
  local ok, request = pcall(function()
    return Curl.get(token_endpoint, {
      headers = {
        Authorization = "Bearer " .. (M._oauth_token or ""),
        Accept = "application/json",
        ["User-Agent"] = "CodeCompanion.nvim",
      },
      insecure = config.adapters.http.opts.allow_insecure,
      proxy = config.adapters.http.opts.proxy,
      on_error = function(err)
        vim.schedule(function()
          log:error("Copilot GHE Adapter: Token request error %s", err)
        end)
      end,
    })
  end)

  _token_fetch_in_progress = false

  if not ok then
    log:error("Copilot GHE Adapter: Could not authorize your GitHub Copilot token: %s", request)
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, request.body or "")
  if not ok or type(decoded) ~= "table" then
    log:error("Copilot GHE Adapter: Could not decode token response: %s", request.body)
    return nil
  end

  M._copilot_token = decoded --[[@as CopilotToken]]
  return M._copilot_token
end

---Get and authorize a GitHub Copilot token
---@param adapter? CodeCompanion.HTTPAdapter
---@return boolean success
function M.init(adapter)
  local _, auth_hostname = M.resolve_endpoints(adapter)
  M._oauth_token = get_oauth_token(adapter)
  if not M._oauth_token then
    log:error("Copilot GHE Adapter: No token found. Please refer to https://github.com/github/copilot.vim")
    return false
  end

  M._copilot_token = get_copilot_token(adapter)
  if not M._copilot_token or vim.tbl_isempty(M._copilot_token) then
    log:error("Copilot GHE Adapter: Could not authorize your GitHub Copilot token")
    return false
  end

  M._cached_host = auth_hostname

  if adapter then
    adapter.url = M._copilot_token.endpoints and (M._copilot_token.endpoints.api .. "/chat/completions") or adapter.url
  end

  return true
end

---Return the Copilot tokens without initializing them
---@param opts? { force: boolean, adapter: CodeCompanion.HTTPAdapter }
---@return { oauth_token: CopilotOAuthToken, copilot_token: CopilotToken|nil }
function M.fetch(opts)
  opts = opts or {}

  -- Only initialize tokens if explicitly requested or if we already have an oauth token cached
  if opts.force or M._oauth_token then
    pcall(M.init, opts.adapter)
  end

  return {
    oauth_token = M._oauth_token,
    copilot_token = (M._copilot_token and M._copilot_token.token) or nil,
    endpoints = (M._copilot_token and M._copilot_token.endpoints) or nil,
  }
end

return M
