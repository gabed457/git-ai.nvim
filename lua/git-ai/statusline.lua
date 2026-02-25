--- Statusline component exports for git-ai.nvim
local M = {}

--- Get a statusline string for the current line
--- Returns e.g., "🤖 copilot:gpt-4o" or ""
---@return string
function M.statusline()
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]

  local cache = require("git-ai.cache")
  local data = cache.get(bufnr)
  if not data then
    return ""
  end

  local attr = data[line]
  if not attr or not attr.is_ai then
    return ""
  end

  local tool = attr.tool or "ai"
  local model = attr.model or "unknown"
  return "🤖 " .. tool .. ":" .. model
end

--- Get a project-level statusline string
--- Returns e.g., "AI: 34%" or ""
---@return string
function M.statusline_project()
  local bufnr = vim.api.nvim_get_current_buf()
  local cache = require("git-ai.cache")
  local ai_lines, _ = cache.get_ai_line_count(bufnr)

  if ai_lines == 0 then
    return ""
  end

  local total = vim.api.nvim_buf_line_count(bufnr)
  if total == 0 then
    return ""
  end

  local pct = math.floor((ai_lines / total) * 100)
  return "AI: " .. pct .. "%"
end

return M
