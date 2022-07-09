M = {}

-- Ensure original config is not copied and `function` is sanitized
function M.fn_wrap_tbl(obj)
  return type(obj) == "function" and { obj } or vim.tbl_deep_extend("force", {}, obj)
end

return M
