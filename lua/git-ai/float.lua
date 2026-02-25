--- Floating window creation and content formatting for git-ai.nvim
local M = {}

--- Active floating window state
---@type { win: number|nil, buf: number|nil, autocmd: number|nil }
local state = { win = nil, buf = nil, autocmd = nil }

--- Close the active floating window
function M.close()
  if state.autocmd then
    pcall(vim.api.nvim_del_autocmd, state.autocmd)
    state.autocmd = nil
  end

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil

  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.buf = nil
end

--- Wrap text to a given width
---@param text string
---@param width number
---@return string[]
local function wrap_text(text, width)
  if not text or text == "" then
    return {}
  end

  local lines = {}
  for _, paragraph in ipairs(vim.split(text, "\n")) do
    if #paragraph <= width then
      table.insert(lines, paragraph)
    else
      local current = ""
      for word in paragraph:gmatch("%S+") do
        if #current + #word + 1 > width then
          if current ~= "" then
            table.insert(lines, current)
          end
          current = word
        else
          current = current == "" and word or (current .. " " .. word)
        end
      end
      if current ~= "" then
        table.insert(lines, current)
      end
    end
  end
  return lines
end

--- Build the content lines and highlights for the attribution float
---@param attr GitAiAttribution
---@param config table
---@return string[] lines, table[] highlights
function M.build_content(attr, config)
  local lines = {}
  local highlights = {} -- { line, col_start, col_end, hl_group }
  local max_width = config.float.max_width - 4 -- padding

  local function add(text, hl)
    table.insert(lines, text)
    if hl then
      table.insert(highlights, {
        line = #lines - 1,
        col_start = 0,
        col_end = #text,
        hl_group = hl,
      })
    end
  end

  local function add_field(label, value, value_hl)
    if not value or value == "" then
      return
    end
    local padded_label = label .. string.rep(" ", math.max(0, 10 - #label))
    local text = "  " .. padded_label .. value
    table.insert(lines, text)
    -- Highlight the label
    table.insert(highlights, {
      line = #lines - 1,
      col_start = 2,
      col_end = 2 + #padded_label,
      hl_group = "GitAiFloatLabel",
    })
    -- Highlight the value
    if value_hl then
      table.insert(highlights, {
        line = #lines - 1,
        col_start = 2 + #padded_label,
        col_end = #text,
        hl_group = value_hl,
      })
    end
  end

  add("") -- top padding

  add_field("Tool:", attr.tool or "unknown", "GitAiFloatTool")
  add_field("Model:", attr.model or "unknown", "GitAiFloatModel")
  add_field("Author:", attr.author or "", nil)
  add_field("Date:", attr.date or "", nil)

  if attr.prompt and attr.prompt ~= "" then
    add("")
    add("  Prompt:", "GitAiFloatLabel")
    add("  " .. string.rep("─", math.min(40, max_width - 2)), "GitAiFloatSeparator")

    local wrapped = wrap_text(attr.prompt, max_width - 2)
    for _, wline in ipairs(wrapped) do
      add("  " .. wline, "GitAiFloatPrompt")
    end
  end

  if attr.line_start and attr.line_end then
    add("")
    if attr.line_start == attr.line_end then
      add_field("Line:", tostring(attr.line_start), nil)
    else
      add_field("Lines:", attr.line_start .. "-" .. attr.line_end, nil)
    end
  end

  if attr.commit then
    add_field("Commit:", attr.commit:sub(1, 7), nil)
  end

  add("") -- bottom padding

  return lines, highlights
end

--- Show a floating window with attribution details for the current line
---@param attr GitAiAttribution|nil
---@param config table
function M.show(attr, config)
  -- Close any existing float
  M.close()

  if not attr then
    vim.notify("No AI attribution for this line", vim.log.levels.INFO)
    return
  end

  if not attr.is_ai then
    vim.notify("No AI attribution for this line", vim.log.levels.INFO)
    return
  end

  local lines, highlights = M.build_content(attr, config)

  -- Calculate window size
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = math.min(width + 4, config.float.max_width)
  width = math.max(width, 30) -- minimum width
  local height = math.min(#lines, config.float.max_height)

  -- Create the buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "git-ai-float"

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("git_ai_float")
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, hl.hl_group, hl.line, hl.col_start, hl.col_end)
  end

  -- Open the floating window
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = config.float.border,
    title = " AI Attribution ",
    title_pos = "center",
  })

  vim.api.nvim_set_option_value("winhl", "FloatBorder:GitAiFloatBorder,NormalFloat:Normal", { win = win })
  vim.api.nvim_set_option_value("wrap", true, { win = win })

  state.win = win
  state.buf = buf

  -- Set up keymaps to close
  vim.keymap.set("n", "q", function()
    M.close()
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", function()
    M.close()
  end, { buffer = buf, nowait = true })

  -- Close on cursor move
  state.autocmd = vim.api.nvim_create_autocmd("CursorMoved", {
    callback = function()
      M.close()
    end,
    once = true,
  })
end

--- Show file-level stats in a floating window
---@param bufnr number
---@param config table
function M.show_stats(bufnr, config)
  local cache = require("git-ai.cache")
  local ai_lines, _ = cache.get_ai_line_count(bufnr)
  local breakdown = cache.get_tool_model_breakdown(bufnr)

  M.close()

  local lines = {}
  local highlights = {}

  table.insert(lines, "")

  -- Get actual line count from buffer
  local buf_lines = vim.api.nvim_buf_line_count(bufnr)
  local pct = buf_lines > 0 and math.floor((ai_lines / buf_lines) * 100) or 0

  table.insert(lines, "  AI-Generated Lines: " .. ai_lines .. " / " .. buf_lines .. " (" .. pct .. "%)")
  table.insert(highlights, {
    line = #lines - 1,
    col_start = 0,
    col_end = #lines[#lines],
    hl_group = "GitAiStatsPct",
  })

  table.insert(lines, "")
  table.insert(lines, "  Breakdown by Tool/Model:")
  table.insert(lines, "  " .. string.rep("─", 40))

  -- Sort breakdown
  local sorted = {}
  for key, count in pairs(breakdown) do
    table.insert(sorted, { key = key, count = count })
  end
  table.sort(sorted, function(a, b)
    return a.count > b.count
  end)

  for _, entry in ipairs(sorted) do
    local bar_len = buf_lines > 0 and math.floor((entry.count / buf_lines) * 30) or 0
    bar_len = math.max(bar_len, 1)
    local bar = string.rep("█", bar_len)
    table.insert(lines, "  " .. entry.key .. ": " .. entry.count .. " lines")
    table.insert(lines, "  " .. bar)
    table.insert(highlights, {
      line = #lines - 1,
      col_start = 2,
      col_end = 2 + bar_len,
      hl_group = "GitAiFloatTool",
    })
  end

  if #sorted == 0 then
    table.insert(lines, "  No AI attribution data found")
  end

  table.insert(lines, "")

  -- Calculate window dimensions
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = math.min(width + 4, config.float.max_width)
  width = math.max(width, 40)
  local height = math.min(#lines, config.float.max_height)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local ns = vim.api.nvim_create_namespace("git_ai_float")
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, hl.hl_group, hl.line, hl.col_start, hl.col_end)
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = config.float.border,
    title = " AI Stats ",
    title_pos = "center",
  })

  vim.api.nvim_set_option_value("winhl", "FloatBorder:GitAiFloatBorder,NormalFloat:Normal", { win = win })

  state.win = win
  state.buf = buf

  vim.keymap.set("n", "q", function()
    M.close()
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", function()
    M.close()
  end, { buffer = buf, nowait = true })
end

--- Show AI log for the current file
---@param bufnr number
---@param config table
function M.show_log(bufnr, config)
  local cache = require("git-ai.cache")
  local prompts = cache.get_prompts(bufnr)

  M.close()

  local lines = {}
  local highlights = {}

  table.insert(lines, "")

  if #prompts == 0 then
    table.insert(lines, "  No AI attribution data found for this file")
    table.insert(lines, "")
  else
    for i, p in ipairs(prompts) do
      local header = string.format(
        "  [%d] %s:%s  (lines %s-%s)  %s",
        i,
        p.tool or "unknown",
        p.model or "unknown",
        p.line_start or "?",
        p.line_end or "?",
        p.commit and p.commit:sub(1, 7) or ""
      )
      table.insert(lines, header)
      table.insert(highlights, {
        line = #lines - 1,
        col_start = 0,
        col_end = #header,
        hl_group = "GitAiFloatTool",
      })

      if p.date then
        table.insert(lines, "      Date: " .. p.date)
      end

      if p.prompt and p.prompt ~= "" then
        table.insert(lines, "      Prompt: " .. p.prompt:sub(1, 120):gsub("\n", " "))
        table.insert(highlights, {
          line = #lines - 1,
          col_start = 6,
          col_end = #lines[#lines],
          hl_group = "GitAiFloatPrompt",
        })
      end

      table.insert(lines, "")
    end
  end

  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = math.min(width + 4, config.float.max_width)
  width = math.max(width, 40)
  local height = math.min(#lines, config.float.max_height)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local ns = vim.api.nvim_create_namespace("git_ai_float")
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, hl.hl_group, hl.line, hl.col_start, hl.col_end)
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = config.float.border,
    title = " AI Attribution Log ",
    title_pos = "center",
  })

  vim.api.nvim_set_option_value("winhl", "FloatBorder:GitAiFloatBorder,NormalFloat:Normal", { win = win })

  state.win = win
  state.buf = buf

  vim.keymap.set("n", "q", function()
    M.close()
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", function()
    M.close()
  end, { buffer = buf, nowait = true })
end

--- Show full AI blame in a side panel
---@param bufnr number
---@param config table
function M.show_blame_panel(bufnr, config)
  local cache_mod = require("git-ai.cache")
  local data = cache_mod.get(bufnr)

  if not data then
    vim.notify("No AI blame data available. Run :GitAiRefresh first.", vim.log.levels.INFO)
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local blame_lines = {}

  for i = 1, line_count do
    local attr = data[i]
    if attr and attr.is_ai then
      local text = string.format(
        "%s:%s",
        attr.tool or "ai",
        attr.model or "unknown"
      )
      table.insert(blame_lines, text)
    else
      table.insert(blame_lines, "")
    end
  end

  -- Find max width
  local max_w = 0
  for _, l in ipairs(blame_lines) do
    max_w = math.max(max_w, #l)
  end
  max_w = math.max(max_w + 2, 20)

  -- Create split
  vim.cmd("topleft " .. max_w .. "vnew")
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, blame_lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "git-ai-blame"

  vim.api.nvim_set_option_value("number", false, { win = win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = win })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = win })
  vim.api.nvim_set_option_value("foldcolumn", "0", { win = win })
  vim.api.nvim_set_option_value("winfixwidth", true, { win = win })
  vim.api.nvim_set_option_value("wrap", false, { win = win })
  vim.api.nvim_set_option_value("cursorline", true, { win = win })

  -- Highlight AI lines
  local ns = vim.api.nvim_create_namespace("git_ai_blame_panel")
  for i, line in ipairs(blame_lines) do
    if line ~= "" then
      vim.api.nvim_buf_add_highlight(buf, ns, "GitAiFloatTool", i - 1, 0, -1)
    end
  end

  -- Scroll sync with original buffer
  local orig_win = vim.fn.win_getid(vim.fn.winnr("#"))
  vim.api.nvim_set_option_value("scrollbind", true, { win = win })
  vim.api.nvim_set_option_value("scrollbind", true, { win = orig_win })
  vim.api.nvim_set_option_value("cursorbind", true, { win = win })
  vim.api.nvim_set_option_value("cursorbind", true, { win = orig_win })

  -- Clean up on close
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(orig_win) then
        vim.api.nvim_set_option_value("scrollbind", false, { win = orig_win })
        vim.api.nvim_set_option_value("cursorbind", false, { win = orig_win })
      end
    end,
  })

  -- Close with q
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, nowait = true })

  -- Go back to original window
  vim.api.nvim_set_current_win(orig_win)
end

return M
