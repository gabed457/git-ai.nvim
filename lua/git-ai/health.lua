--- Health check for git-ai.nvim
--- Run with :checkhealth git-ai
local M = {}

function M.check()
  vim.health.start("git-ai.nvim")

  -- Check git-ai CLI
  if vim.fn.executable("git-ai") == 1 then
    vim.health.ok("git-ai CLI found on PATH")

    -- Get version
    local version = vim.fn.systemlist({ "git-ai", "--version" })
    if vim.v.shell_error == 0 and #version > 0 then
      vim.health.ok("git-ai version: " .. version[1])
    else
      vim.health.info("Could not determine git-ai version")
    end
  else
    vim.health.error("git-ai CLI not found", {
      "Install git-ai: curl -sSL https://usegitai.com/install.sh | bash",
      "See: https://github.com/acunniffe/git-ai",
    })
  end

  -- Check git
  if vim.fn.executable("git") == 1 then
    vim.health.ok("git found on PATH")
  else
    vim.health.error("git not found on PATH")
  end

  -- Check if in a git repo
  local git_dir = vim.fn.finddir(".git", vim.fn.getcwd() .. ";")
  if git_dir ~= "" then
    vim.health.ok("Current directory is a git repository")
  else
    vim.health.warn("Current directory is not a git repository")
  end

  -- Check for AI notes
  local notes = vim.fn.systemlist({ "git", "notes", "--ref=refs/notes/ai", "list" })
  if vim.v.shell_error == 0 and #notes > 0 and notes[1] ~= "" then
    vim.health.ok("Git AI notes found (" .. #notes .. " entries)")
  else
    vim.health.info("No Git AI notes found in this repository")
  end

  -- Check Neovim version
  if vim.fn.has("nvim-0.9.0") == 1 then
    vim.health.ok("Neovim version >= 0.9.0")
  else
    vim.health.error("Neovim >= 0.9.0 required")
  end

  -- Check telescope (optional)
  local has_telescope = pcall(require, "telescope")
  if has_telescope then
    vim.health.ok("telescope.nvim found (optional)")
  else
    vim.health.info("telescope.nvim not found (optional, needed for :GitAiPrompts and :GitAiSearch)")
  end
end

return M
