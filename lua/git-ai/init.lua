--- git-ai.nvim — Neovim plugin for Git AI attribution
--- Inline virtual text, floating windows, sign column, and telescope integration
--- for viewing which lines of code were AI-generated.
local M = {}

---@type table
M.config = {}

---@type boolean
M._enabled = false

---@type boolean
M._setup_done = false

--- Default configuration
local defaults = {
  enabled = true,

  virtual_text = {
    enabled = true,
    format = "🤖 {tool}:{model}",
    hl_group = "GitAiVirtualText",
    current_line_only = false,
  },

  signs = {
    enabled = true,
    char = "▍",
    priority = 5,
    colors = { "#7aa2f7", "#9ece6a", "#e0af68", "#f7768e", "#bb9af7", "#7dcfff" },
  },

  float = {
    border = "rounded",
    max_width = 80,
    max_height = 20,
  },

  blame = {
    debounce = 300,
    auto_refresh_events = { "BufWritePost", "BufEnter" },
  },

  keymaps = {
    hover = "<leader>ai",
    toggle = "<leader>at",
    blame = "<leader>ab",
    stats = "<leader>as",
    prompts = "<leader>ap",
    search = "<leader>aS",
  },

  telescope = {
    preview = true,
  },
}

--- Deep merge two tables (b values override a)
---@param a table
---@param b table
---@return table
local function deep_merge(a, b)
  local result = vim.deepcopy(a)
  for k, v in pairs(b) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = deep_merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

--- Autocmd group
local augroup = vim.api.nvim_create_augroup("GitAi", { clear = true })

--- Attached buffers
---@type table<number, boolean>
local attached = {}

--- Update the display for a buffer (virtual text + signs)
---@param bufnr number
---@param data table<number, GitAiAttribution>|nil
local function update_display(bufnr, data)
  if not M._enabled or not data then
    require("git-ai.virtual_text").clear(bufnr)
    require("git-ai.signs").clear(bufnr)
    return
  end

  require("git-ai.virtual_text").render(bufnr, data, M.config)
  require("git-ai.signs").render(bufnr, data, M.config)
end

--- Attach to a buffer — start tracking AI attribution
---@param bufnr number
local function attach(bufnr)
  if attached[bufnr] then
    return
  end

  local utils = require("git-ai.utils")
  if not utils.is_normal_buffer(bufnr) then
    return
  end

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then
    return
  end

  -- Check if file is in a git repo
  local dir = vim.fn.fnamemodify(filepath, ":h")
  if not utils.is_git_repo(dir) then
    return
  end

  attached[bufnr] = true

  -- Initial blame (debounced)
  local blame = require("git-ai.blame")
  local debounced_fn = blame.debounced_blame(bufnr, M.config.blame.debounce, function(data)
    update_display(bufnr, data)
  end)
  debounced_fn()

  -- Set up auto-refresh events for this buffer
  for _, event in ipairs(M.config.blame.auto_refresh_events) do
    vim.api.nvim_create_autocmd(event, {
      group = augroup,
      buffer = bufnr,
      callback = function()
        if M._enabled and attached[bufnr] then
          debounced_fn()
        end
      end,
    })
  end

  -- Clear extmarks on text change to avoid stale positions
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      require("git-ai.virtual_text").clear(bufnr)
      require("git-ai.signs").clear(bufnr)
    end,
  })

  -- Handle current_line_only mode
  if M.config.virtual_text.current_line_only then
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = augroup,
      buffer = bufnr,
      callback = function()
        if M._enabled then
          local cache = require("git-ai.cache")
          local data = cache.get(bufnr)
          if data then
            require("git-ai.virtual_text").render(bufnr, data, M.config)
          end
        end
      end,
    })
  end

  -- Clean up on buffer delete
  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    buffer = bufnr,
    once = true,
    callback = function()
      attached[bufnr] = nil
      require("git-ai.cache").invalidate(bufnr)
      require("git-ai.blame").clear_debounce(bufnr)
    end,
  })
end

--- Setup the plugin
---@param opts? table user configuration
function M.setup(opts)
  if M._setup_done then
    return
  end
  M._setup_done = true

  -- Merge config
  M.config = deep_merge(defaults, opts or {})

  -- Check prerequisites
  local utils = require("git-ai.utils")
  if not utils.is_git_ai_installed() then
    -- Silently disable — no error spam
    return
  end

  -- Setup highlights
  require("git-ai.highlights").setup()
  require("git-ai.highlights").setup_sign_colors(M.config.signs.colors)

  -- Setup commands and keymaps
  require("git-ai.commands").setup(M.config)
  require("git-ai.keymaps").setup(M.config)

  -- Enable
  M._enabled = M.config.enabled

  if M._enabled then
    -- Attach to existing buffers
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) then
        attach(bufnr)
      end
    end

    -- Attach to new buffers
    vim.api.nvim_create_autocmd("BufEnter", {
      group = augroup,
      callback = function(args)
        if M._enabled then
          attach(args.buf)
        end
      end,
    })

    -- Invalidate cache on focus gained (catches external git commits)
    vim.api.nvim_create_autocmd("FocusGained", {
      group = augroup,
      callback = function()
        require("git-ai.cache").clear()
        for bufnr in pairs(attached) do
          if vim.api.nvim_buf_is_valid(bufnr) and M._enabled then
            local blame = require("git-ai.blame")
            blame.request_blame(bufnr, function(data)
              update_display(bufnr, data)
            end)
          end
        end
      end,
    })
  end

  -- Register telescope extension if available
  pcall(function()
    require("telescope").load_extension("git_ai")
  end)
end

--- Toggle virtual text on/off
function M.toggle()
  M._enabled = not M._enabled

  if M._enabled then
    -- Re-attach and refresh all loaded buffers
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) then
        attach(bufnr)
      end
    end
    vim.notify("git-ai: enabled", vim.log.levels.INFO)
  else
    -- Clear all displays
    for bufnr in pairs(attached) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        require("git-ai.virtual_text").clear(bufnr)
        require("git-ai.signs").clear(bufnr)
      end
    end
    vim.notify("git-ai: disabled", vim.log.levels.INFO)
  end
end

--- Show hover float for the current line
function M.hover()
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]

  local blame = require("git-ai.blame")
  local attr = blame.get_line_attribution(bufnr, line)

  require("git-ai.float").show(attr, M.config)
end

--- Force refresh blame for the current buffer
function M.refresh()
  local bufnr = vim.api.nvim_get_current_buf()
  require("git-ai.cache").invalidate(bufnr)

  local blame = require("git-ai.blame")
  blame.request_blame(bufnr, function(data)
    update_display(bufnr, data)
    vim.notify("git-ai: blame refreshed", vim.log.levels.INFO)
  end, { force = true })
end

--- Get the statusline string for the current line
---@return string
function M.statusline()
  return require("git-ai.statusline").statusline()
end

--- Get the project-level statusline string
---@return string
function M.statusline_project()
  return require("git-ai.statusline").statusline_project()
end

return M
