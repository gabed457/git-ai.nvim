--- Default highlight group definitions for git-ai.nvim
local M = {}

--- Define default highlight groups (user can override)
function M.setup()
  local groups = {
    GitAiVirtualText = { fg = "#565f89", italic = true },
    GitAiSign = { fg = "#7aa2f7" },
    GitAiFloatBorder = { fg = "#7aa2f7" },
    GitAiFloatTitle = { fg = "#7aa2f7", bold = true },
    GitAiFloatTool = { fg = "#9ece6a", bold = true },
    GitAiFloatModel = { fg = "#e0af68", bold = true },
    GitAiFloatPrompt = { fg = "#a9b1d6" },
    GitAiFloatLabel = { fg = "#565f89" },
    GitAiFloatSeparator = { fg = "#3b4261" },
    GitAiStatsPct = { fg = "#f7768e", bold = true },
  }

  for name, opts in pairs(groups) do
    -- Use default = true so user overrides take precedence
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end
end

--- Define sign highlight groups from a color palette
---@param colors string[] list of hex color strings
function M.setup_sign_colors(colors)
  for i, color in ipairs(colors) do
    vim.api.nvim_set_hl(0, "GitAiSign" .. i, { fg = color, default = true })
  end
end

return M
