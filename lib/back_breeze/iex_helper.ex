defmodule BackBreeze.IExHelpers do
  import IEx.Helpers

  def r, do: recompile()
  def rf, do: recompile(force: true)
end
