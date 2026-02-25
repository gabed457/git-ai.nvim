--- Telescope extension for git-ai.nvim
--- Provides pickers for browsing AI-generated code

local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  return
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")

--- GitAiPrompts picker — list all prompts in the current file
local function prompts_picker(opts)
  opts = opts or {}

  local bufnr = vim.api.nvim_get_current_buf()
  local cache = require("git-ai.cache")
  local prompt_list = cache.get_prompts(bufnr)

  if #prompt_list == 0 then
    vim.notify("No AI prompts found for this file", vim.log.levels.INFO)
    return
  end

  local entries = {}
  for _, p in ipairs(prompt_list) do
    local summary = ""
    if p.prompt and p.prompt ~= "" then
      summary = p.prompt:sub(1, 80):gsub("\n", " ")
    end

    table.insert(entries, {
      display = string.format(
        "%s:%s  L%s-%s  %s",
        p.tool or "unknown",
        p.model or "unknown",
        p.line_start or "?",
        p.line_end or "?",
        summary
      ),
      tool = p.tool or "unknown",
      model = p.model or "unknown",
      line_start = p.line_start or 1,
      line_end = p.line_end or 1,
      prompt = p.prompt or "",
      date = p.date or "",
      commit = p.commit or "",
      ordinal = (p.tool or "") .. " " .. (p.model or "") .. " " .. (p.prompt or ""),
    })
  end

  pickers
    .new(opts, {
      prompt_title = "AI Prompts",
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display,
            ordinal = entry.ordinal,
            lnum = entry.line_start,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_buffer_previewer({
        title = "Prompt Details",
        define_preview = function(self, entry)
          local p = entry.value
          local lines = {
            "Tool:    " .. p.tool,
            "Model:   " .. p.model,
            "Date:    " .. p.date,
            "Commit:  " .. p.commit,
            "Lines:   " .. p.line_start .. "-" .. p.line_end,
            "",
            "Prompt:",
            "─────────────────────────────────",
          }
          for _, line in ipairs(vim.split(p.prompt, "\n")) do
            table.insert(lines, line)
          end
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection and selection.lnum then
            vim.api.nvim_win_set_cursor(0, { selection.lnum, 0 })
          end
        end)
        return true
      end,
    })
    :find()
end

--- GitAiSearch picker — search across all AI-attributed code in the project
local function search_picker(opts)
  opts = opts or {}

  local utils = require("git-ai.utils")
  local root = utils.git_root()
  if not root then
    vim.notify("Not in a git repository", vim.log.levels.WARN)
    return
  end

  vim.notify("Searching for AI-attributed code in project...", vim.log.levels.INFO)

  -- Get list of tracked files
  local files = vim.fn.systemlist({ "git", "-C", root, "ls-files" })
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to list git files", vim.log.levels.ERROR)
    return
  end

  local blame = require("git-ai.blame")
  local all_entries = {}
  local pending = #files
  local max_files = 100 -- limit to avoid overwhelming

  if pending > max_files then
    files = vim.list_slice(files, 1, max_files)
    pending = max_files
  end

  local function check_done()
    pending = pending - 1
    if pending > 0 then
      return
    end

    if #all_entries == 0 then
      vim.notify("No AI-attributed code found in project", vim.log.levels.INFO)
      return
    end

    -- Sort by file then line
    table.sort(all_entries, function(a, b)
      if a.filename == b.filename then
        return a.lnum < b.lnum
      end
      return a.filename < b.filename
    end)

    pickers
      .new(opts, {
        prompt_title = "AI Code Search",
        finder = finders.new_table({
          results = all_entries,
          entry_maker = function(entry)
            return {
              value = entry,
              display = entry.display,
              ordinal = entry.ordinal,
              filename = entry.filepath,
              lnum = entry.lnum,
            }
          end,
        }),
        sorter = conf.generic_sorter(opts),
        previewer = conf.file_previewer(opts),
        attach_mappings = function(prompt_bufnr, map)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            if selection then
              vim.cmd("edit " .. vim.fn.fnameescape(selection.filename))
              if selection.lnum then
                vim.api.nvim_win_set_cursor(0, { selection.lnum, 0 })
              end
            end
          end)
          return true
        end,
      })
      :find()
  end

  for _, file in ipairs(files) do
    local filepath = root .. "/" .. file
    -- Skip binary files and very large files
    if vim.fn.filereadable(filepath) == 1 then
      blame.run_blame(filepath, function(err, data)
        if not err and data then
          for line_nr, attr in pairs(data) do
            if attr.is_ai then
              table.insert(all_entries, {
                display = string.format("%s:%d  %s:%s", file, line_nr, attr.tool or "ai", attr.model or "unknown"),
                ordinal = file .. " " .. (attr.tool or "") .. " " .. (attr.model or "") .. " " .. (attr.prompt or ""),
                filename = file,
                filepath = filepath,
                lnum = line_nr,
                tool = attr.tool,
                model = attr.model,
              })
            end
          end
        end
        vim.schedule(check_done)
      end, { json = true })
    else
      vim.schedule(check_done)
    end
  end
end

return telescope.register_extension({
  exports = {
    prompts = prompts_picker,
    search = search_picker,
  },
})
