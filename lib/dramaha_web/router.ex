defmodule DramahaWeb.Router do
  use DramahaWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {DramahaWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", DramahaWeb do
    pipe_through :browser

    live "/", PageLive, :index
    live "/sessions/new", SessionsLive.New
    live "/sessions/:session_uuid/join", SessionsLive.Join
    live "/sessions/:session_uuid/play", PlayLive.Play

    post "/sessions/:session_uuid/register", RegistrationController, :register
  end

  # Other scopes may use custom stacks.
  # scope "/api", DramahaWeb do
  #   pipe_through :api
  # end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: DramahaWeb.Telemetry
    end
  end
end
