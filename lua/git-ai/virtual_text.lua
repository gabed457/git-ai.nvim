--- Virtual text rendering via extmarks for git-ai.nvim
local M = {}

local ns = vim.api.nvim_create_namespace("git_ai_virtual_text")

--- Format the virtual text string from attribution data
---@param attr GitAiAttribution
---@param format_str string format template with {tool}, {model}, {author}, {date}
---@return string
function M.format_text(attr, format_str)
  local text = format_str
  text = text:gsub("{tool}", attr.tool or "ai")
  text = text:gsub("{model}", attr.model or "unknown")
  text = text:gsub("{author}", attr.author or "")
  text = text:gsub("{date}", attr.date or "")
  return text
end

--- Render virtual text for a buffer
---@param bufnr number
---@param data table<number, GitAiAttribution>
---@param config table plugin configuration
function M.render(bufnr, data, config)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local vt_config = config.virtual_text
  if not vt_config.enabled then
    return
  end

  -- Clear existing virtual text
  M.clear(bufnr)

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local current_line = vim.api.nvim_win_get_cursor(0)[1]

  for line_nr, attr in pairs(data) do
    if attr.is_ai and line_nr <= line_count then
      -- If current_line_only is set, only show on the current line
      if vt_config.current_line_only and line_nr ~= current_line then
        goto continue
      end

      local text = M.format_text(attr, vt_config.format)

      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line_nr - 1, 0, {
        virt_text = { { "  " .. text, vt_config.hl_group } },
        virt_text_pos = "eol",
        hl_mode = "combine",
      })

      ::continue::
    end
  end
end

--- Clear all virtual text from a buffer
---@param bufnr number
function M.clear(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
end

--- Update virtual text for current line only mode
---@param bufnr number
---@param data table<number, GitAiAttribution>
---@param config table
function M.update_current_line(bufnr, data, config)
  if not config.virtual_text.current_line_only then
    return
  end
  M.render(bufnr, data, config)
end

--- Get the namespace ID (for external use)
---@return number
function M.get_namespace()
  return ns
end

return M
