import Config

if config_env() == :test do
  config :back_breeze, render_cache_max_memory_bytes: 4 * 1_024 * 1_024
end
