local api = vim.api
local extmarks = require "resin.extmarks"
local Path = require "plenary.path"

local M = {}

local function write_file(path, contents)
  local fd = assert(vim.loop.fs_open(path, "w", 438))
  vim.loop.fs_write(fd, contents, -1)
  assert(vim.loop.fs_close(fd))
end

local function read_file(path)
  local fd = vim.loop.fs_open(path, "r", 438)
  local stat = vim.loop.fs_fstat(fd)
  local data = vim.loop.fs_read(fd, stat.size, 0)
  assert(vim.loop.fs_close(fd))
  return data
end

M.read_history = function(path)
  local history_path = vim.F.if_nil(path, require("resin").config.history.path)
  local history
  if vim.fn.filereadable(history_path) == 1 then
    -- format: { filename = { string<time> = { begin = begin_pos, end_pos = end_pos } } }
    history = vim.json.decode(read_file(history_path))
    -- format: { bufnr = { number<time> = { begin = begin_pos, end_pos = end_pos } } }
  else
    history = {}
  end
  local extmarks_ = extmarks.get_marks_positions()
  for bufnr, buffer_marks in pairs(extmarks_) do
    local bufname = api.nvim_buf_get_name(bufnr)
    for time, pos in pairs(buffer_marks) do
      if not history[bufname] then
        history[bufname] = {}
      end
      history[bufname][tostring(time)] = pos
    end
  end
  return history
end

M.convert = function(history)
  local ret = {}
  local bufs = vim.api.nvim_list_bufs()
  local bufnames = {}
  for _, buf in ipairs(bufs) do
    if api.nvim_buf_is_loaded(buf) then
      bufnames[api.nvim_buf_get_name(buf)] = buf
    end
  end
  for filename, filehistory in pairs(history) do
    ret[filename] = {}
    local bufnr = bufnames[filename]
    local cleanup_buf = false
    if bufnr == nil then
      local data = Path:new(filename):read()
      local processed_data = {}
      for line in vim.gsplit(data, "[\r]?\n") do
        table.insert(processed_data, line)
      end
      table.remove(processed_data)
      bufnr = api.nvim_create_buf(false, true)
      api.nvim_buf_set_lines(bufnr, 0, -1, false, processed_data)
      cleanup_buf = true
    end
    for timestamp, value in pairs(filehistory) do
      local data
      if value.begin_pos then
        local begin_pos = value.begin_pos
        local end_pos = value.end_pos
        local max_len = api.nvim_buf_line_count(bufnr) - 1
        local last_line = api.nvim_buf_get_lines(bufnr, max_len, -1, false)[1]
        -- end of file may be intermittently deleted
        data = api.nvim_buf_get_text(
          bufnr,
          begin_pos[1],
          begin_pos[2],
          max_len < end_pos[1] and max_len or end_pos[1],
          max_len < end_pos[1] and #last_line or end_pos[2] + 1,
          {}
        )
      else
        data = value
      end
      ret[filename][tostring(timestamp)] = data
    end
    if cleanup_buf then
      api.nvim_buf_delete(bufnr, { force = true, unload = false })
    end
  end
  return ret
end

M.truncate_history = function(history, limit)
  local timestamps = {}
  for _, filehistory in pairs(history) do
    for timestamp, _ in pairs(filehistory) do
      table.insert(timestamps, tonumber(timestamp))
    end
  end
  table.sort(timestamps, function(x, y)
    return x > y
  end)
  local cutoff = timestamps[math.min(#timestamps, limit)]
  for _, filehistory in pairs(history) do
    for timestamp, _ in pairs(filehistory) do
      if tonumber(timestamp) < cutoff then
        filehistory[timestamp] = nil
      end
    end
  end
  return history
end

M.add_entry = function(history, entry)
  if not history[entry.filename] then
    history[entry.filename] = {}
  end
  history[entry.filename][entry.time] = entry.data
end

M.write = function(history, opts)
  opts = opts or {}
  opts.convert = vim.F.if_nil(opts.convert, false)
  local history_config = require("resin").config.history
  if opts.convert then
    history = M.convert(history)
  end
  if type(history_config.limit) == "number" then
    if not vim.tbl_isempty(history) then
      history = M.truncate_history(history, history_config.limit)
    end
  end
  local json_obj = vim.json.encode(history)
  write_file(history_config.path, json_obj)
end

return M
