--- Utility functions for git-ai.nvim
--- CLI detection, async job helpers, path utilities
local M = {}

--- Check if git-ai CLI is installed
---@return boolean
function M.is_git_ai_installed()
  return vim.fn.executable("git-ai") == 1
end

--- Check if the current working directory is inside a git repository
---@param path? string directory to check (defaults to cwd)
---@return boolean
function M.is_git_repo(path)
  path = path or vim.fn.getcwd()
  local git_dir = vim.fn.finddir(".git", path .. ";")
  return git_dir ~= ""
end

--- Get the git root directory for a given path
---@param path? string file or directory path
---@return string|nil
function M.git_root(path)
  path = path or vim.fn.getcwd()
  local result = vim.fn.systemlist({ "git", "-C", path, "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 or #result == 0 then
    return nil
  end
  return result[1]
end

--- Get the current git HEAD hash
---@param path? string directory path
---@return string|nil
function M.git_head(path)
  path = path or vim.fn.getcwd()
  local result = vim.fn.systemlist({ "git", "-C", path, "rev-parse", "HEAD" })
  if vim.v.shell_error ~= 0 or #result == 0 then
    return nil
  end
  return result[1]
end

--- Get the file path relative to the git root
---@param filepath string absolute file path
---@return string|nil relative path
function M.git_relative_path(filepath)
  local dir = vim.fn.fnamemodify(filepath, ":h")
  local result = vim.fn.systemlist({ "git", "-C", dir, "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 or #result == 0 then
    return nil
  end
  local root = result[1]
  if vim.startswith(filepath, root) then
    return filepath:sub(#root + 2) -- +2 to skip the trailing /
  end
  return filepath
end

--- Run a command asynchronously using vim.fn.jobstart
---@param cmd string[] command and arguments
---@param callback fun(err: string|nil, stdout: string[])
---@return number|nil job_id
function M.job_run(cmd, callback)
  local stdout = {}
  local stderr = {}

  local job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        stdout = data
      end
    end,
    on_stderr = function(_, data)
      if data then
        stderr = data
      end
    end,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        -- Remove trailing empty strings from buffered output
        while #stdout > 0 and stdout[#stdout] == "" do
          table.remove(stdout)
        end
        while #stderr > 0 and stderr[#stderr] == "" do
          table.remove(stderr)
        end

        if exit_code == 0 then
          callback(nil, stdout)
        else
          callback(table.concat(stderr, "\n"), nil)
        end
      end)
    end,
  })

  if job_id <= 0 then
    callback("Failed to start job: " .. table.concat(cmd, " "), nil)
    return nil
  end

  return job_id
end

--- Run a git-ai CLI command asynchronously
---@param args string[] arguments to pass to git-ai
---@param callback fun(err: string|nil, stdout: string[])
---@param opts? { cwd?: string }
---@return number|nil job_id
function M.run_git_ai(args, callback, opts)
  local cmd = { "git-ai" }
  for _, arg in ipairs(args) do
    table.insert(cmd, arg)
  end

  local stdout = {}
  local stderr = {}

  local job_opts = {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        stdout = data
      end
    end,
    on_stderr = function(_, data)
      if data then
        stderr = data
      end
    end,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        while #stdout > 0 and stdout[#stdout] == "" do
          table.remove(stdout)
        end
        while #stderr > 0 and stderr[#stderr] == "" do
          table.remove(stderr)
        end

        if exit_code == 0 then
          callback(nil, stdout)
        else
          callback(table.concat(stderr, "\n"), nil)
        end
      end)
    end,
  }

  if opts and opts.cwd then
    job_opts.cwd = opts.cwd
  end

  local job_id = vim.fn.jobstart(cmd, job_opts)
  if job_id <= 0 then
    callback("Failed to start git-ai: " .. table.concat(cmd, " "), nil)
    return nil
  end

  return job_id
end

--- Create a debounced version of a function
---@param fn function the function to debounce
---@param ms number debounce delay in milliseconds
---@return function debounced function
function M.debounce(fn, ms)
  local timer = vim.uv.new_timer()
  return function(...)
    local args = { ... }
    timer:stop()
    timer:start(ms, 0, function()
      timer:stop()
      vim.schedule(function()
        fn(unpack(args))
      end)
    end)
  end
end

--- Check if a buffer is a normal file buffer worth processing
---@param bufnr number
---@return boolean
function M.is_normal_buffer(bufnr)
  local buftype = vim.bo[bufnr].buftype
  if buftype ~= "" then
    return false
  end

  local filetype = vim.bo[bufnr].filetype
  if filetype == "" then
    return false
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return false
  end

  -- Check if file exists
  if vim.fn.filereadable(name) ~= 1 then
    return false
  end

  return true
end

--- Check if a file is likely binary
---@param filepath string
---@return boolean
function M.is_binary(filepath)
  local result = vim.fn.systemlist({ "file", "--mime-encoding", filepath })
  if vim.v.shell_error ~= 0 or #result == 0 then
    return false
  end
  return result[1]:find("binary") ~= nil
end

--- Get the git-ai CLI version string
---@param callback fun(version: string|nil)
function M.get_version(callback)
  M.run_git_ai({ "--version" }, function(err, stdout)
    if err or not stdout or #stdout == 0 then
      callback(nil)
      return
    end
    callback(stdout[1])
  end)
end

return M
