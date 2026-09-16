defmodule KarakuriWeb.PageController do
  use KarakuriWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
