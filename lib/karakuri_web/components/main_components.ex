defmodule KarakuriWeb.MainComponents do
  use Phoenix.Component

  slot :inner_block, required: true

  def main_title(assigns) do
    ~H"""
    <h1 class="text-2xl font-bold mb-3">
      {render_slot(@inner_block)}
    </h1>
    """
  end
end
