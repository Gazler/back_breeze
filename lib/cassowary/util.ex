defmodule Cassowary.Util do
  @epsilon 1.0e-8
  def near_zero?(value, epsilon \\ @epsilon) when is_float(value), do: abs(value) < epsilon
end
