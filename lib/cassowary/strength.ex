defmodule Cassowary.Strength do
  @type t :: float()

  @required 1_000_000_000.0
  def required(), do: @required
  @strong 1000.0
  def strong(), do: @strong
  @medium 1.0
  def medium(), do: @medium
  @weak 0.001
  def weak(), do: @weak

  defguard is_strength(strength) when strength >= @weak and strength <= @required

  def new(strength) when is_float(strength) do
    strength
    |> max(weak())
    |> min(required())
  end
end
