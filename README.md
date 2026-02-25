# git-ai.nvim

Neovim plugin for [Git AI](https://usegitai.com) attribution — see which lines of code were AI-generated, by which tool, model, and prompt, right inside your editor.

Think of it as **gitsigns.nvim but for AI authorship**.

<!-- TODO: Add GIF/screenshot showing virtual text, floating window, and sign column -->

## Features

- [x] **Inline virtual text** — shows `🤖 tool:model` at the end of AI-generated lines
- [x] **Floating window** — hover on any line to see full attribution: tool, model, author, date, and prompt
- [x] **Sign column indicators** — colored markers group lines from the same AI prompt
- [x] **Telescope integration** — browse prompts per-file or search AI code project-wide
- [x] **Statusline component** — export for lualine or any statusline plugin
- [x] **Full blame panel** — scroll-synced side panel showing AI attribution for every line
- [x] **File stats** — percentage AI-generated, breakdown by tool/model
- [x] **Health check** — `:checkhealth git-ai` to verify your setup

## Why?

AI-generated code is a growing part of every codebase. Understanding which lines came from AI — and what prompt produced them — is critical for:

- **Code review**: Know which sections to scrutinize more carefully
- **Debugging**: Trace bugs back to the AI prompt that introduced them
- **Maintenance**: Understand the intent behind AI-generated code
- **Compliance**: Track AI usage for organizational policies
- **Learning**: See how different tools and models approach problems

## Requirements

- Neovim >= 0.9.0
- [git-ai CLI](https://usegitai.com) installed
- git

**Optional:**
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for picker features
- [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) for icons in telescope results

### Install git-ai CLI

```bash
curl -sSL https://usegitai.com/install.sh | bash
```

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "gabed457/git-ai.nvim",
  event = "BufReadPre",
  opts = {},
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "gabed457/git-ai.nvim",
  config = function()
    require("git-ai").setup()
  end,
}
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'gabed457/git-ai.nvim'

" In your init.lua or after/plugin:
lua require('git-ai').setup()
```

## Configuration

All options with their defaults:

```lua
require("git-ai").setup({
  -- Enable/disable on startup
  enabled = true,

  -- Virtual text configuration
  virtual_text = {
    enabled = true,
    -- Format string. Available tokens: {tool}, {model}, {author}, {date}
    format = "🤖 {tool}:{model}",
    -- Highlight group for virtual text
    hl_group = "GitAiVirtualText",
    -- Only show on current line (like gitsigns current_line_blame)
    current_line_only = false,
  },

  -- Sign column configuration
  signs = {
    enabled = true,
    -- Character to use for AI-generated lines
    char = "▍",
    -- Priority (relative to gitsigns, which defaults to 6)
    priority = 5,
    -- Color palette for grouping prompts (rotating)
    colors = {
      "#7aa2f7", "#9ece6a", "#e0af68",
      "#f7768e", "#bb9af7", "#7dcfff",
    },
  },

  -- Floating window configuration
  float = {
    border = "rounded",
    max_width = 80,
    max_height = 20,
  },

  -- Blame configuration
  blame = {
    -- Debounce time in ms before running blame after buffer change
    debounce = 300,
    -- Auto-refresh blame after these events
    auto_refresh_events = { "BufWritePost", "BufEnter" },
  },

  -- Keymaps (set to false to disable any keymap)
  keymaps = {
    hover = "<leader>ai",       -- Show AI attribution for current line
    toggle = "<leader>at",      -- Toggle virtual text
    blame = "<leader>ab",       -- Full AI blame side panel
    stats = "<leader>as",       -- File stats
    prompts = "<leader>ap",     -- Telescope prompts picker
    search = "<leader>aS",      -- Telescope project search
  },

  -- Telescope configuration
  telescope = {
    preview = true,
  },
})
```

## Commands

| Command | Description |
|---|---|
| `:GitAiToggle` | Toggle inline virtual text on/off |
| `:GitAiBlame` | Show full AI blame side panel |
| `:GitAiHover` | Show floating window for current line |
| `:GitAiStats` | Show file-level stats (% AI, tool/model breakdown) |
| `:GitAiLog` | Show AI attribution log for the current file |
| `:GitAiPrompts` | Open telescope picker for prompts in current file |
| `:GitAiSearch` | Open telescope picker for project-wide AI code search |
| `:GitAiRefresh` | Force refresh the blame cache for the current buffer |

## Keybinds

| Keybind | Action |
|---|---|
| `<leader>ai` | Show AI attribution for current line |
| `<leader>at` | Toggle virtual text on/off |
| `<leader>ab` | Full AI blame side panel |
| `<leader>as` | File stats |
| `<leader>ap` | Telescope prompts picker |
| `<leader>aS` | Telescope project-wide AI code search |

## Statusline

```lua
-- For lualine
require("lualine").setup({
  sections = {
    lualine_x = {
      -- Current line attribution: "🤖 copilot:gpt-4o"
      { function() return require("git-ai").statusline() end },
      -- File-level stats: "AI: 34%"
      { function() return require("git-ai").statusline_project() end },
    },
  },
})
```

## Health Check

Run `:checkhealth git-ai` to verify your setup:

```
git-ai: require("git-ai.health").check()

git-ai.nvim
- OK git-ai CLI found on PATH
- OK git-ai version: 0.3.2
- OK Current directory is a git repository
- OK Git AI notes found (42 entries)
- OK Neovim version >= 0.9.0
- OK telescope.nvim found (optional)
```

## How It Works

This plugin reads AI attribution data that [Git AI](https://usegitai.com) stores in [Git Notes](https://git-scm.com/docs/git-notes). It runs the `git-ai blame` CLI asynchronously and never blocks your editor. All data is cached per-buffer and automatically refreshed on file save or when returning to a buffer.

The plugin does **not** generate code or call any AI APIs — it only reads and displays existing attribution data.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run the linter: `stylua --check lua/`
5. Run tests: `nvim --headless -l tests/blame_parser_spec.lua`
6. Submit a pull request

## License

MIT — see [LICENSE](LICENSE)
