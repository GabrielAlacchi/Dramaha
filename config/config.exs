# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :dramaha,
  ecto_repos: [Dramaha.Repo]

# Configures the endpoint
config :dramaha, DramahaWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "2Sk62V5F+ACH2RIEXeVsoD1QwbPHneDzr1r9U+QuJYJPLnV0JBE5kZ7UV7rlob48",
  render_errors: [view: DramahaWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Dramaha.PubSub,
  live_view: [signing_salt: "4Xzu7K3/"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
