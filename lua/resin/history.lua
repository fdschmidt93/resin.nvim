local a = vim.api

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
  vim.loop.fs_close(fd)
  return data
end

M.read_history = function()
  local history_path = require("resin").config.history.path
  if vim.fn.filereadable(history_path) == 1 then
    return vim.json.decode(read_file(history_path))
  end
  return {}
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

M.write_history = function(bufnr, data)
  local filename = a.nvim_buf_get_name(bufnr)
  local history_config = require("resin").config.history
  local history = M.read_history()
  if not history[filename] then
    history[filename] = {}
  end
  history[filename][tostring(os.time())] = data
  if type(history_config.limit) == "number" then
    if not vim.tbl_isempty(history) then
      history = M.truncate_history(history, history_config.limit)
    end
  end
  local json_obj = vim.json.encode(history)
  write_file(history_config.path, json_obj)
end

return M
