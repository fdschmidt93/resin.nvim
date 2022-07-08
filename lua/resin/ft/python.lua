-- DISCLAIMER: only works with ipython
return {
  on_before_receive = function(receiver, data)
    receiver:receiver_fn { "%cpaste -q\n" } -- sending ipython header
    vim.wait(50) -- cpaste otherwise doesn't properly work
    table.insert(data, "--\n")
  end,
}
