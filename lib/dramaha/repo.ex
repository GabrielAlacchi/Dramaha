defmodule Dramaha.Repo do
  use Ecto.Repo,
    otp_app: :dramaha,
    adapter: Ecto.Adapters.Postgres
end
