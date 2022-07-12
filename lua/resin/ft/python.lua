-- DISCLAIMER: only works with ipython
return {
  on_before_receive = function(receiver)
    receiver:receiver_fn { "%cpaste -q" } -- sending ipython header
    vim.wait(50) -- cpaste otherwise doesn't properly work
  end,
  on_after_receive = function(receiver)
    receiver:receiver_fn { "--" } -- sending ipython header
  end
}
