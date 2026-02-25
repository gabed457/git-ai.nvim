--- Blame result caching and invalidation for git-ai.nvim
local uv = vim.uv or vim.loop

local M = {}

---@class GitAiAttribution
---@field tool string|nil AI tool name (e.g., "cursor", "copilot")
---@field model string|nil model name (e.g., "gpt-4o", "claude-sonnet-4-5")
---@field author string|nil human author
---@field date string|nil date string
---@field prompt string|nil the prompt text
---@field commit string|nil commit hash
---@field line_start number|nil start line of the prompt block
---@field line_end number|nil end line of the prompt block
---@field session_id string|nil session identifier
---@field is_ai boolean whether this line is AI-generated
---@field prompt_id string|nil unique identifier for grouping lines from the same prompt

---@class GitAiCacheEntry
---@field data table<number, GitAiAttribution> line number -> attribution
---@field head string git HEAD hash at time of cache
---@field timestamp number cache creation time
---@field filepath string file path

--- Cache storage keyed by buffer number
---@type table<number, GitAiCacheEntry>
local cache = {}

--- Store blame data for a buffer
---@param bufnr number buffer number
---@param filepath string file path
---@param head string git HEAD hash
---@param data table<number, GitAiAttribution> line attribution data
function M.set(bufnr, filepath, head, data)
  cache[bufnr] = {
    data = data,
    head = head,
    timestamp = uv.now(),
    filepath = filepath,
  }
end

--- Get cached blame data for a buffer
---@param bufnr number buffer number
---@return table<number, GitAiAttribution>|nil
function M.get(bufnr)
  local entry = cache[bufnr]
  if not entry then
    return nil
  end
  return entry.data
end

--- Check if cache is valid for a buffer
---@param bufnr number
---@param filepath string
---@param head string current git HEAD
---@return boolean
function M.is_valid(bufnr, filepath, head)
  local entry = cache[bufnr]
  if not entry then
    return false
  end
  return entry.filepath == filepath and entry.head == head
end

--- Invalidate cache for a specific buffer
---@param bufnr number
function M.invalidate(bufnr)
  cache[bufnr] = nil
end

--- Invalidate all caches for a given file path
---@param filepath string
function M.invalidate_by_path(filepath)
  for bufnr, entry in pairs(cache) do
    if entry.filepath == filepath then
      cache[bufnr] = nil
    end
  end
end

--- Clear all cached data
function M.clear()
  cache = {}
end

--- Get cache entry metadata (for debugging/stats)
---@param bufnr number
---@return GitAiCacheEntry|nil
function M.get_entry(bufnr)
  return cache[bufnr]
end

--- Get number of AI-attributed lines from cache
---@param bufnr number
---@return number ai_lines, number total_lines
function M.get_ai_line_count(bufnr)
  local entry = cache[bufnr]
  if not entry then
    return 0, 0
  end

  local ai_count = 0
  local max_line = 0
  for line, attr in pairs(entry.data) do
    if attr.is_ai then
      ai_count = ai_count + 1
    end
    if line > max_line then
      max_line = line
    end
  end

  return ai_count, max_line
end

--- Get unique prompts from cache
---@param bufnr number
---@return GitAiAttribution[] list of unique prompt attributions
function M.get_prompts(bufnr)
  local entry = cache[bufnr]
  if not entry then
    return {}
  end

  local seen = {}
  local prompts = {}
  for _, attr in pairs(entry.data) do
    if attr.is_ai and attr.prompt_id and not seen[attr.prompt_id] then
      seen[attr.prompt_id] = true
      table.insert(prompts, attr)
    end
  end

  -- Sort by line_start
  table.sort(prompts, function(a, b)
    return (a.line_start or 0) < (b.line_start or 0)
  end)

  return prompts
end

--- Get tool/model breakdown from cache
---@param bufnr number
---@return table<string, number> tool:model -> line count
function M.get_tool_model_breakdown(bufnr)
  local entry = cache[bufnr]
  if not entry then
    return {}
  end

  local breakdown = {}
  for _, attr in pairs(entry.data) do
    if attr.is_ai then
      local key = (attr.tool or "unknown") .. ":" .. (attr.model or "unknown")
      breakdown[key] = (breakdown[key] or 0) + 1
    end
  end

  return breakdown
end

return M
