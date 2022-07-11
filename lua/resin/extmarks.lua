local a = vim.api
local resin_ns = vim.api.nvim_create_namespace "ResinMarks"
local M = {}

M._marks = {}

function M.add(begin_extmark_id, end_extmark_id)
  local bufnr = a.nvim_get_current_buf()
  if not M._marks[bufnr] then
    M._marks[bufnr] = {}
  end
  M._marks[bufnr][os.time()] = { begin_extmark_id = begin_extmark_id, end_extmark_id = end_extmark_id }
end

function M.get_marks()
  return M._marks
end

function M.get_marks_positions()
  local ret = {}
  for bufnr, extmarks in pairs(M._marks) do
    local bufnr_extmarks = {}
    for time, mark in pairs(extmarks) do
      bufnr_extmarks[time] = {
        begin_pos = a.nvim_buf_get_extmark_by_id(bufnr, resin_ns, mark.begin_extmark_id, {}),
        end_pos = a.nvim_buf_get_extmark_by_id(bufnr, resin_ns, mark.end_extmark_id, {}),
      }
    end
    ret[bufnr] = bufnr_extmarks
  end
  return ret
end

function M.get_text_by_id(bufnr, begin_extmark_id, end_extmark_id)
  local begin_pos = a.nvim_buf_get_extmark_by_id(bufnr, resin_ns, begin_extmark_id, {})
  local end_pos = a.nvim_buf_get_extmark_by_id(bufnr, resin_ns, end_extmark_id, {})
  local data = a.nvim_buf_get_text(bufnr, begin_pos[1], begin_pos[2], end_pos[1], end_pos[2] + 1, {})
  return data
end

return M
