defmodule BackBreeze.RenderCache.MemoryLimit do
  @moduledoc false

  @compile {:no_warn_undefined, :memsup}

  require Logger

  @default_bytes 256 * 1_024 * 1_024
  @maximum_bytes 1_024 * 1_024 * 1_024
  @ratio_numerator 7
  @ratio_denominator 10

  def resolve do
    case Application.get_env(:back_breeze, :render_cache_max_memory_bytes, :auto) do
      :auto ->
        automatic_limit()

      bytes when is_integer(bytes) and bytes > 0 ->
        bytes

      value ->
        raise ArgumentError,
              ":back_breeze, :render_cache_max_memory_bytes must be :auto or a positive integer, got: #{inspect(value)}"
    end
  end

  @doc false
  def limit_for_available_memory(bytes) when is_integer(bytes) and bytes >= 0 do
    bytes
    |> Kernel.*(@ratio_numerator)
    |> div(@ratio_denominator)
    |> min(@maximum_bytes)
    |> max(1)
  end

  defp automatic_limit do
    case available_memory_bytes() do
      {:ok, bytes} ->
        limit_for_available_memory(bytes)

      :error ->
        Logger.warning(
          "BackBreeze could not read available system memory because OTP's :memsup " <>
            "is unavailable. Using the default 256 MiB render cache limit. Add :os_mon " <>
            "to your application's extra_applications to enable automatic sizing, or " <>
            "configure :back_breeze, :render_cache_max_memory_bytes explicitly."
        )

        @default_bytes
    end
  end

  defp available_memory_bytes do
    if Process.whereis(:memsup) do
      case :memsup.get_system_memory_data() do
        data when is_list(data) ->
          case Keyword.get(data, :available_memory) do
            bytes when is_integer(bytes) and bytes >= 0 -> {:ok, bytes}
            _other -> available_memory_from_summary()
          end

        _other ->
          available_memory_from_summary()
      end
    else
      :error
    end
  catch
    :exit, _reason -> :error
  end

  defp available_memory_from_summary do
    case :memsup.get_memory_data() do
      {total, allocated, _worst}
      when is_integer(total) and is_integer(allocated) and total > 0 ->
        {:ok, max(total - allocated, 0)}

      _other ->
        :error
    end
  end
end
