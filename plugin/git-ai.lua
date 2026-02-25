--- Lazy autoload trigger for git-ai.nvim
--- Only loads the plugin when entering a git repository

if vim.g.loaded_git_ai then
  return
end
vim.g.loaded_git_ai = true

-- Require Neovim >= 0.9
if vim.fn.has("nvim-0.9.0") ~= 1 then
  return
end

-- Defer loading until VimEnter to avoid slowing down startup
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    -- Only auto-setup if the user hasn't called setup manually
    -- (setup() guards against double-init)
    vim.schedule(function()
      local git_ai = require("git-ai")
      if not git_ai._setup_done then
        -- Don't auto-setup — let the user call require('git-ai').setup()
        -- This file just ensures the plugin module is available
      end
    end)
  end,
})
