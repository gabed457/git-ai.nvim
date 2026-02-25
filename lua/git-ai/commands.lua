--- User command definitions for git-ai.nvim
local M = {}

--- Register all user commands
---@param config table plugin configuration
function M.setup(config)
  vim.api.nvim_create_user_command("GitAiToggle", function()
    require("git-ai").toggle()
  end, { desc = "Toggle git-ai inline virtual text" })

  vim.api.nvim_create_user_command("GitAiBlame", function()
    local float = require("git-ai.float")
    float.show_blame_panel(vim.api.nvim_get_current_buf(), config)
  end, { desc = "Show full AI blame side panel" })

  vim.api.nvim_create_user_command("GitAiHover", function()
    require("git-ai").hover()
  end, { desc = "Show AI attribution for current line" })

  vim.api.nvim_create_user_command("GitAiStats", function()
    local float = require("git-ai.float")
    float.show_stats(vim.api.nvim_get_current_buf(), config)
  end, { desc = "Show file-level AI stats" })

  vim.api.nvim_create_user_command("GitAiLog", function()
    local float = require("git-ai.float")
    float.show_log(vim.api.nvim_get_current_buf(), config)
  end, { desc = "Show AI attribution log for current file" })

  vim.api.nvim_create_user_command("GitAiPrompts", function()
    local ok, telescope = pcall(require, "telescope")
    if ok then
      telescope.extensions.git_ai.prompts()
    else
      vim.notify("Telescope is required for :GitAiPrompts", vim.log.levels.WARN)
    end
  end, { desc = "Open telescope picker for AI prompts in current file" })

  vim.api.nvim_create_user_command("GitAiSearch", function()
    local ok, telescope = pcall(require, "telescope")
    if ok then
      telescope.extensions.git_ai.search()
    else
      vim.notify("Telescope is required for :GitAiSearch", vim.log.levels.WARN)
    end
  end, { desc = "Open telescope picker for project-wide AI code search" })

  vim.api.nvim_create_user_command("GitAiRefresh", function()
    require("git-ai").refresh()
  end, { desc = "Force refresh AI blame cache for current buffer" })
end

return M
