defmodule KarakuriWeb.HomeLiveTest do
  use KarakuriWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the home page and workflow link", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#home-page")
    assert has_element?(view, "#home-page h1", "Karakuri")
    assert has_element?(view, "#start-here[href='/workflows']", "Start here")
    refute has_element?(view, "header.navbar")
    refute has_element?(view, "button[data-phx-theme]")
  end
end
