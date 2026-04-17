defmodule BackBreeze.TextSpan do
  @moduledoc """
  A styled run of text that can participate in shared text layout.
  """

  defstruct text: "", style: %{}

  def new(text, style \\ %{}) when is_binary(text) and is_map(style) do
    %__MODULE__{text: text, style: style}
  end
end
