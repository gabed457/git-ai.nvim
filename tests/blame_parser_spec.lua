--- Tests for the git-ai blame parser and cache logic
--- Run with: nvim -l tests/blame_parser_spec.lua

-- Setup package path from project root
local root = vim.fn.getcwd()
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

-- Minimal test runner
local test_results = { passed = 0, failed = 0, errors = {} }

local function describe(name, fn)
  print("\n" .. name)
  fn()
end

local function it(name, fn)
  local ok, err = pcall(fn)
  if ok then
    test_results.passed = test_results.passed + 1
    print("  ✓ " .. name)
  else
    test_results.failed = test_results.failed + 1
    table.insert(test_results.errors, { name = name, err = err })
    print("  ✗ " .. name)
    print("    " .. tostring(err))
  end
end

local function assert_eq(expected, actual, msg)
  if expected ~= actual then
    error(string.format(
      "%sexpected %s, got %s",
      msg and (msg .. ": ") or "",
      vim.inspect(expected),
      vim.inspect(actual)
    ))
  end
end

-- Load modules under test
local blame = require("git-ai.blame")
local cache = require("git-ai.cache")

describe("blame parser", function()
  describe("parse_blame_line", function()
    it("should parse an AI-generated line with session ID", function()
      local line = "fe2c4c8 (claude [session_abc123] 2025-12-02 19:25:13 -0500 138) local x = 1"
      local result = blame.parse_blame_line(line)

      assert(result, "result should not be nil")
      assert_eq(true, result.is_ai)
      assert_eq("claude", result.tool)
      assert_eq("session_abc123", result.session_id)
      assert_eq("2025-12-02 19:25:13", result.date)
      assert_eq("fe2c4c8", result.commit)
      assert_eq(138, result.line_start)
    end)

    it("should parse a human-authored line without session ID", function()
      local line = "a1b2c3d (John Doe 2025-11-15 10:30:00 -0500 42) function foo()"
      local result = blame.parse_blame_line(line)

      assert(result, "result should not be nil")
      assert_eq(false, result.is_ai)
      assert_eq("John Doe", result.author)
      assert_eq("2025-11-15 10:30:00", result.date)
      assert_eq("a1b2c3d", result.commit)
      assert_eq(42, result.line_start)
    end)

    it("should return nil for empty lines", function()
      assert_eq(nil, blame.parse_blame_line(""))
      assert_eq(nil, blame.parse_blame_line(nil))
    end)

    it("should parse a line with cursor as the tool", function()
      local line = "abc1234 (cursor [sess_xyz] 2026-01-10 08:00:00 +0000 10) return true"
      local result = blame.parse_blame_line(line)

      assert(result, "result should not be nil")
      assert_eq(true, result.is_ai)
      assert_eq("cursor", result.tool)
      assert_eq("sess_xyz", result.session_id)
      assert_eq(10, result.line_start)
    end)

    it("should handle minimal commit hash", function()
      local line = "abcdef0 (copilot [s1] 2026-02-01 12:00:00 +0000 1) x"
      local result = blame.parse_blame_line(line)

      assert(result, "result should not be nil")
      assert_eq(true, result.is_ai)
      assert_eq("copilot", result.tool)
    end)
  end)

  describe("parse_text_blame", function()
    it("should parse multiple lines and group by session", function()
      local lines = {
        "abc1234 (claude [sess_1] 2025-12-02 10:00:00 -0500 1) line one",
        "abc1234 (claude [sess_1] 2025-12-02 10:00:00 -0500 2) line two",
        "abc1234 (claude [sess_1] 2025-12-02 10:00:00 -0500 3) line three",
        "def5678 (John Doe 2025-12-01 09:00:00 -0500 4) human line",
        "ghi9012 (cursor [sess_2] 2025-12-03 11:00:00 -0500 5) cursor line",
      }

      local result = blame.parse_text_blame(lines)

      assert(result[1], "line 1 should exist")
      assert_eq(true, result[1].is_ai)
      assert_eq("claude", result[1].tool)
      assert_eq("sess_1", result[1].prompt_id)

      assert(result[2], "line 2 should exist")
      assert_eq(true, result[2].is_ai)
      assert_eq("sess_1", result[2].prompt_id)

      assert(result[4], "line 4 should exist")
      assert_eq(false, result[4].is_ai)
      assert_eq("John Doe", result[4].author)

      assert(result[5], "line 5 should exist")
      assert_eq(true, result[5].is_ai)
      assert_eq("cursor", result[5].tool)
      assert_eq("sess_2", result[5].prompt_id)
    end)

    it("should handle empty input", function()
      local result = blame.parse_text_blame({})
      assert(result, "result should not be nil")
      local count = 0
      for _ in pairs(result) do
        count = count + 1
      end
      assert_eq(0, count)
    end)

    it("should update line_start and line_end for blocks", function()
      local lines = {
        "abc1234 (claude [sess_1] 2025-12-02 10:00:00 -0500 10) a",
        "abc1234 (claude [sess_1] 2025-12-02 10:00:00 -0500 11) b",
        "abc1234 (claude [sess_1] 2025-12-02 10:00:00 -0500 12) c",
      }

      local result = blame.parse_text_blame(lines)

      -- All lines in the block should share the same start/end
      assert_eq(10, result[10].line_start)
      assert_eq(12, result[10].line_end)
      assert_eq(10, result[11].line_start)
      assert_eq(12, result[11].line_end)
      assert_eq(10, result[12].line_start)
      assert_eq(12, result[12].line_end)
    end)
  end)
end)

describe("cache", function()
  it("should store and retrieve data", function()
    cache.clear()

    local data = {
      [1] = { is_ai = true, tool = "claude", model = "sonnet", prompt_id = "s1" },
      [2] = { is_ai = false, author = "John" },
    }

    cache.set(1, "/test/file.lua", "abc123", data)

    local retrieved = cache.get(1)
    assert(retrieved, "cached data should not be nil")
    assert_eq(true, retrieved[1].is_ai)
    assert_eq("claude", retrieved[1].tool)
    assert_eq(false, retrieved[2].is_ai)
  end)

  it("should validate cache with matching path and head", function()
    cache.clear()

    local data = { [1] = { is_ai = true, tool = "test" } }
    cache.set(1, "/test/file.lua", "abc123", data)

    assert_eq(true, cache.is_valid(1, "/test/file.lua", "abc123"))
    assert_eq(false, cache.is_valid(1, "/test/file.lua", "def456"))
    assert_eq(false, cache.is_valid(1, "/test/other.lua", "abc123"))
    assert_eq(false, cache.is_valid(2, "/test/file.lua", "abc123"))
  end)

  it("should invalidate specific buffers", function()
    cache.clear()

    cache.set(1, "/file1.lua", "head1", { [1] = { is_ai = true } })
    cache.set(2, "/file2.lua", "head2", { [1] = { is_ai = true } })

    cache.invalidate(1)

    assert_eq(nil, cache.get(1))
    assert(cache.get(2), "buffer 2 should still be cached")
  end)

  it("should invalidate by file path", function()
    cache.clear()

    cache.set(1, "/shared/file.lua", "head1", { [1] = { is_ai = true } })
    cache.set(2, "/shared/file.lua", "head2", { [1] = { is_ai = true } })
    cache.set(3, "/other/file.lua", "head3", { [1] = { is_ai = true } })

    cache.invalidate_by_path("/shared/file.lua")

    assert_eq(nil, cache.get(1))
    assert_eq(nil, cache.get(2))
    assert(cache.get(3), "buffer 3 should still be cached")
  end)

  it("should count AI lines correctly", function()
    cache.clear()

    cache.set(1, "/test.lua", "head", {
      [1] = { is_ai = true, tool = "claude" },
      [2] = { is_ai = true, tool = "cursor" },
      [3] = { is_ai = false, author = "human" },
      [5] = { is_ai = true, tool = "copilot" },
    })

    local ai_count, max_line = cache.get_ai_line_count(1)
    assert_eq(3, ai_count)
    assert_eq(5, max_line)
  end)

  it("should get tool/model breakdown", function()
    cache.clear()

    cache.set(1, "/test.lua", "head", {
      [1] = { is_ai = true, tool = "claude", model = "sonnet" },
      [2] = { is_ai = true, tool = "claude", model = "sonnet" },
      [3] = { is_ai = true, tool = "cursor", model = "gpt-4o" },
      [4] = { is_ai = false },
    })

    local breakdown = cache.get_tool_model_breakdown(1)
    assert_eq(2, breakdown["claude:sonnet"])
    assert_eq(1, breakdown["cursor:gpt-4o"])
  end)

  it("should clear all caches", function()
    cache.set(1, "/a.lua", "h1", { [1] = { is_ai = true } })
    cache.set(2, "/b.lua", "h2", { [1] = { is_ai = true } })

    cache.clear()

    assert_eq(nil, cache.get(1))
    assert_eq(nil, cache.get(2))
  end)

  it("should get unique prompts sorted by line", function()
    cache.clear()

    cache.set(1, "/test.lua", "head", {
      [10] = { is_ai = true, tool = "claude", prompt_id = "s1", line_start = 10, line_end = 12 },
      [11] = { is_ai = true, tool = "claude", prompt_id = "s1", line_start = 10, line_end = 12 },
      [12] = { is_ai = true, tool = "claude", prompt_id = "s1", line_start = 10, line_end = 12 },
      [20] = { is_ai = true, tool = "cursor", prompt_id = "s2", line_start = 20, line_end = 22 },
      [21] = { is_ai = true, tool = "cursor", prompt_id = "s2", line_start = 20, line_end = 22 },
      [30] = { is_ai = false, author = "human" },
    })

    local prompts = cache.get_prompts(1)
    assert_eq(2, #prompts)
    assert_eq("s1", prompts[1].prompt_id)
    assert_eq("s2", prompts[2].prompt_id)
    assert_eq("claude", prompts[1].tool)
    assert_eq("cursor", prompts[2].tool)
  end)
end)

-- Print summary and exit
print(string.format("\n%d passed, %d failed", test_results.passed, test_results.failed))
if #test_results.errors > 0 then
  print("\nFailed tests:")
  for _, err in ipairs(test_results.errors) do
    print("  " .. err.name .. ": " .. tostring(err.err))
  end
  os.exit(1)
else
  os.exit(0)
end
