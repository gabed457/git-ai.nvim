--- Keymap setup for git-ai.nvim
local M = {}

--- Set up keymaps based on configuration
---@param config table plugin configuration
function M.setup(config)
  local keymaps = config.keymaps
  if not keymaps then
    return
  end

  if keymaps.hover then
    vim.keymap.set("n", keymaps.hover, function()
      require("git-ai").hover()
    end, { desc = "Show AI attribution for current line" })
  end

  if keymaps.toggle then
    vim.keymap.set("n", keymaps.toggle, function()
      require("git-ai").toggle()
    end, { desc = "Toggle git-ai virtual text" })
  end

  if keymaps.blame then
    vim.keymap.set("n", keymaps.blame, function()
      local float = require("git-ai.float")
      float.show_blame_panel(vim.api.nvim_get_current_buf(), config)
    end, { desc = "Show full AI blame side panel" })
  end

  if keymaps.stats then
    vim.keymap.set("n", keymaps.stats, function()
      local float = require("git-ai.float")
      float.show_stats(vim.api.nvim_get_current_buf(), config)
    end, { desc = "Show AI stats for current file" })
  end

  if keymaps.prompts then
    vim.keymap.set("n", keymaps.prompts, function()
      local ok, telescope = pcall(require, "telescope")
      if ok then
        telescope.extensions.git_ai.prompts()
      else
        vim.notify("Telescope is required for AI prompts picker", vim.log.levels.WARN)
      end
    end, { desc = "Open AI prompts telescope picker" })
  end

  if keymaps.search then
    vim.keymap.set("n", keymaps.search, function()
      local ok, telescope = pcall(require, "telescope")
      if ok then
        telescope.extensions.git_ai.search()
      else
        vim.notify("Telescope is required for AI search", vim.log.levels.WARN)
      end
    end, { desc = "Open AI search telescope picker" })
  end
end

return M
