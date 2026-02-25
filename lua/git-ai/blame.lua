--- Core blame logic for git-ai.nvim
--- Runs the git-ai CLI, parses output, and manages the cache
local utils = require("git-ai.utils")
local cache = require("git-ai.cache")

local M = {}

--- Active blame jobs per buffer (to cancel stale requests)
---@type table<number, number>
local active_jobs = {}

--- Debounced blame functions per buffer
---@type table<number, function>
local debounced = {}

--- Parse a git-ai blame line in the standard format
--- Expected format: `<commit> (<author> [session_id] <date> <time> <tz> <line>) <code>`
--- Or for AI lines: `<commit> (<agent> [session_id] <date> <time> <tz> <line>) <code>`
---@param line string a single line from git-ai blame output
---@return GitAiAttribution|nil
function M.parse_blame_line(line)
  if not line or line == "" then
    return nil
  end

  -- Try to parse the standard git-ai blame format
  -- Pattern: commit_hash (author [session_id] date time tz linenr) code
  -- Or: commit_hash (author date time tz linenr) code (no session)
  local commit, rest = line:match("^(%x+)%s+%((.+)%)")
  if not commit or not rest then
    -- Try alternate format without parentheses
    commit = line:match("^(%x+)")
    if not commit then
      return nil
    end
    rest = line:sub(#commit + 1)
  end

  -- Try to extract session ID in brackets (indicates AI-generated)
  local author, session_id, date, time_str, _, line_nr =
    rest:match("^(.-)%s+%[([^%]]+)%]%s+(%d%d%d%d%-%d%d%-%d%d)%s+(%d%d:%d%d:%d%d)%s+([%+%-]%d+)%s+(%d+)")

  if author and session_id then
    -- This is an AI-generated line (has session ID)
    return {
      is_ai = true,
      tool = author:match("^%s*(.-)%s*$"), -- trim whitespace, this is the agent name
      model = nil, -- model info may come from detailed query
      author = nil,
      date = date .. " " .. time_str,
      commit = commit,
      session_id = session_id,
      prompt = nil,
      line_start = tonumber(line_nr),
      line_end = tonumber(line_nr),
      prompt_id = session_id, -- group by session
    }
  end

  -- Try without session ID (human-authored line)
  local h_author, h_date, h_time, _, h_line =
    rest:match("^(.-)%s+(%d%d%d%d%-%d%d%-%d%d)%s+(%d%d:%d%d:%d%d)%s+([%+%-]%d+)%s+(%d+)")

  if h_author then
    return {
      is_ai = false,
      tool = nil,
      model = nil,
      author = h_author:match("^%s*(.-)%s*$"),
      date = h_date .. " " .. h_time,
      commit = commit,
      session_id = nil,
      prompt = nil,
      line_start = tonumber(h_line),
      line_end = tonumber(h_line),
      prompt_id = nil,
    }
  end

  -- Minimal fallback: just commit hash
  return {
    is_ai = false,
    commit = commit,
    line_start = nil,
    line_end = nil,
  }
end

--- Parse JSON blame output from git-ai blame --json
---@param json_str string JSON string
---@return table<number, GitAiAttribution>|nil parsed line data
function M.parse_json_blame(json_str)
  local ok, data = pcall(vim.json.decode, json_str)
  if not ok or not data then
    return nil
  end

  local result = {}

  -- Handle the case where data is an array of line entries
  if vim.islist(data) then
    for _, entry in ipairs(data) do
      local line_nr = entry.line or entry.line_number or entry.lineno
      if line_nr then
        local is_ai = entry.is_ai
          or entry.ai
          or (entry.agent ~= nil and entry.agent ~= "")
          or (entry.tool ~= nil and entry.tool ~= "")
          or (entry.session_id ~= nil and entry.session_id ~= "")

        result[line_nr] = {
          is_ai = is_ai and true or false,
          tool = entry.agent or entry.tool,
          model = entry.model,
          author = entry.author or entry.human_author,
          date = entry.date or entry.timestamp,
          commit = entry.commit or entry.sha,
          session_id = entry.session_id or entry.session,
          prompt = entry.prompt or entry.message,
          line_start = entry.line_start or entry.block_start or line_nr,
          line_end = entry.line_end or entry.block_end or line_nr,
          prompt_id = entry.session_id or entry.prompt_id or entry.session,
        }
      end
    end
    return result
  end

  -- Handle object with "lines" key
  if data.lines and vim.islist(data.lines) then
    return M.parse_json_blame(vim.json.encode(data.lines))
  end

  return nil
end

--- Parse the standard text blame output from git-ai blame
---@param lines string[] output lines from git-ai blame
---@return table<number, GitAiAttribution>
function M.parse_text_blame(lines)
  local result = {}

  -- Track consecutive AI lines with the same session for grouping
  local current_session = nil
  local block_start = nil

  for _, line in ipairs(lines) do
    local attr = M.parse_blame_line(line)
    if attr and attr.line_start then
      local line_nr = attr.line_start

      -- Track prompt blocks (consecutive AI lines with same session)
      if attr.is_ai and attr.session_id then
        if attr.session_id == current_session then
          -- Continue the same block
          attr.line_start = block_start
        else
          -- New block
          current_session = attr.session_id
          block_start = line_nr
        end
      else
        current_session = nil
        block_start = nil
      end

      result[line_nr] = attr
    end
  end

  -- Second pass: update line_end for blocks
  local sessions = {}
  for line_nr, attr in pairs(result) do
    if attr.is_ai and attr.prompt_id then
      if not sessions[attr.prompt_id] then
        sessions[attr.prompt_id] = { min = line_nr, max = line_nr }
      else
        sessions[attr.prompt_id].min = math.min(sessions[attr.prompt_id].min, line_nr)
        sessions[attr.prompt_id].max = math.max(sessions[attr.prompt_id].max, line_nr)
      end
    end
  end

  for _, attr in pairs(result) do
    if attr.is_ai and attr.prompt_id and sessions[attr.prompt_id] then
      attr.line_start = sessions[attr.prompt_id].min
      attr.line_end = sessions[attr.prompt_id].max
    end
  end

  return result
end

--- Run git-ai blame for a file and parse the output
---@param filepath string absolute path to the file
---@param callback fun(err: string|nil, data: table<number, GitAiAttribution>|nil)
---@param opts? { json?: boolean }
function M.run_blame(filepath, callback, opts)
  opts = opts or {}

  local dir = vim.fn.fnamemodify(filepath, ":h")
  local rel_path = utils.git_relative_path(filepath)
  if not rel_path then
    callback("Could not determine git-relative path", nil)
    return
  end

  local args = { "blame" }

  -- Try JSON output first if requested
  if opts.json then
    table.insert(args, "--json")
  end

  table.insert(args, rel_path)

  utils.run_git_ai(args, function(err, stdout)
    if err then
      -- If --json failed, retry without it
      if opts.json then
        M.run_blame(filepath, callback, { json = false })
        return
      end
      callback(err, nil)
      return
    end

    if not stdout or #stdout == 0 then
      callback(nil, {})
      return
    end

    local data

    -- Try JSON parse first
    if opts.json then
      local json_str = table.concat(stdout, "\n")
      data = M.parse_json_blame(json_str)
      if data then
        callback(nil, data)
        return
      end
    end

    -- Fall back to text parsing
    data = M.parse_text_blame(stdout)
    callback(nil, data)
  end, { cwd = dir })
end

--- Request blame data for a buffer (with caching and debouncing)
---@param bufnr number
---@param callback fun(data: table<number, GitAiAttribution>|nil)
---@param opts? { force?: boolean }
function M.request_blame(bufnr, callback, opts)
  opts = opts or {}

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then
    return
  end

  if not utils.is_normal_buffer(bufnr) then
    return
  end

  local dir = vim.fn.fnamemodify(filepath, ":h")
  local head = utils.git_head(dir)
  if not head then
    return
  end

  -- Check cache
  if not opts.force and cache.is_valid(bufnr, filepath, head) then
    callback(cache.get(bufnr))
    return
  end

  -- Cancel any active job for this buffer
  if active_jobs[bufnr] then
    pcall(vim.fn.jobstop, active_jobs[bufnr])
    active_jobs[bufnr] = nil
  end

  M.run_blame(filepath, function(err, data)
    active_jobs[bufnr] = nil

    if err then
      -- Silently ignore errors
      callback(nil)
      return
    end

    if data then
      cache.set(bufnr, filepath, head, data)
    end

    callback(data)
  end, { json = true })
end

--- Get a debounced blame request function for a buffer
---@param bufnr number
---@param delay_ms number debounce delay
---@param callback fun(data: table<number, GitAiAttribution>|nil)
---@return function
function M.debounced_blame(bufnr, delay_ms, callback)
  if not debounced[bufnr] then
    debounced[bufnr] = utils.debounce(function()
      M.request_blame(bufnr, callback)
    end, delay_ms)
  end
  return debounced[bufnr]
end

--- Clear debounce tracking for a buffer
---@param bufnr number
function M.clear_debounce(bufnr)
  debounced[bufnr] = nil
end

--- Get blame data for a specific line (from cache)
---@param bufnr number
---@param line number 1-indexed line number
---@return GitAiAttribution|nil
function M.get_line_attribution(bufnr, line)
  local data = cache.get(bufnr)
  if not data then
    return nil
  end
  return data[line]
end

return M
