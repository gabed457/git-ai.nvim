--- Sign column rendering for git-ai.nvim
local M = {}

local ns = vim.api.nvim_create_namespace("git_ai_signs")

--- Assign a color index to each prompt_id (rotating palette)
---@param data table<number, GitAiAttribution>
---@param num_colors number size of color palette
---@return table<string, number> prompt_id -> color index (1-based)
function M.assign_prompt_colors(data, num_colors)
  local mapping = {}
  local next_color = 1

  -- Collect prompt_ids in line order
  local lines = {}
  for line_nr, attr in pairs(data) do
    if attr.is_ai and attr.prompt_id then
      table.insert(lines, { line = line_nr, pid = attr.prompt_id })
    end
  end
  table.sort(lines, function(a, b)
    return a.line < b.line
  end)

  for _, entry in ipairs(lines) do
    if not mapping[entry.pid] then
      mapping[entry.pid] = next_color
      next_color = (next_color % num_colors) + 1
    end
  end

  return mapping
end

--- Render sign column indicators for a buffer
---@param bufnr number
---@param data table<number, GitAiAttribution>
---@param config table plugin configuration
function M.render(bufnr, data, config)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local signs_config = config.signs
  if not signs_config.enabled then
    return
  end

  -- Clear existing signs
  M.clear(bufnr)

  local num_colors = #signs_config.colors
  local color_map = M.assign_prompt_colors(data, num_colors)
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  for line_nr, attr in pairs(data) do
    if attr.is_ai and line_nr <= line_count then
      local color_idx = 1
      if attr.prompt_id and color_map[attr.prompt_id] then
        color_idx = color_map[attr.prompt_id]
      end

      local hl_group = "GitAiSign" .. color_idx

      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line_nr - 1, 0, {
        sign_text = signs_config.char,
        sign_hl_group = hl_group,
        priority = signs_config.priority,
      })
    end
  end
end

--- Clear all signs from a buffer
---@param bufnr number
function M.clear(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
end

--- Get the namespace ID
---@return number
function M.get_namespace()
  return ns
end

return M
