local api = vim.api

M = {}

local resin_ns = vim.api.nvim_create_namespace "Resin"

local REGTYPES = { line = "V", char = "v", block = "" }

-- adapted from hl on yank
function M.hl_on_send(opts)
  opts = opts or {}
  local regtype = vim.F.if_nil(REGTYPES[opts.regtype], "v")
  local higroup = opts.hl_group or "IncSearch"
  local timeout = opts.timeout or 300
  local inclusive = vim.F.if_nil(opts.inclusive, true)

  local bufnr = api.nvim_get_current_buf()
  api.nvim_buf_clear_namespace(bufnr, resin_ns, 0, -1)

  -- begin_pos = { begin_pos[2] - 1, begin_pos[3] - 1 + begin_pos[4] }
  -- end_pos = { end_pos[2] - 1, end_pos[3] - 1 + end_pos[4] }

  vim.highlight.range(
    bufnr,
    resin_ns,
    higroup,
    { opts.begin_pos[1] - 1, opts.begin_pos[2] },
    { opts.end_pos[1] - 1, opts.end_pos[2] },
    { regtype = regtype, inclusive = inclusive, priority = 200 }
  )

  vim.defer_fn(function()
    if api.nvim_buf_is_valid(bufnr) then
      api.nvim_buf_clear_namespace(bufnr, resin_ns, 0, -1)
    end
  end, timeout)
end

-- Ensure original config is not copied and `function` is sanitized
function M.fn_wrap_tbl(obj)
  return type(obj) == "function" and { obj } or vim.tbl_deep_extend("force", {}, obj)
end

return M
