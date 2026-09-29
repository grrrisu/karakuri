defmodule KarakuriWeb.HomeLive do
  use KarakuriWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Karakuri")}
  end

  def render(assigns) do
    ~H"""
    <style :type={KarakuriWeb.ColocatedCSS} phx-no-curly-interpolation>
      @keyframes home-button-pulse {
        0%, 100% {
          transform: scale(1);
        }

        50% {
          transform: scale(1.045);
        }
      }

      #start-here {
        animation: home-button-pulse 2.2s ease-in-out infinite;
      }

      @media (prefers-reduced-motion: reduce) {
        #start-here {
          animation: none;
        }
      }
    </style>
    <section
      id="home-page"
      class="flex min-h-[calc(100svh-3.5rem)] flex-col items-center justify-center gap-6 text-center"
    >
      <div class="relative size-64 sm:size-80" aria-hidden="true">
        <svg
          class="absolute inset-0 size-full"
          viewBox="0 0 100 100"
          xmlns="http://www.w3.org/2000/svg"
        >
          <polygon
            points="50,25 90,90 10,90"
            fill="var(--color-base-100)"
            stroke="var(--color-base-content)"
            stroke-width="1.5"
          />
        </svg>
        <img
          src={~p"/images/tea.png"}
          alt=""
          class="absolute left-[28%] top-[45%] w-[44%] object-contain"
        />
      </div>
      <h1 class="text-6xl text-base-content sm:text-8xl">Karakuri</h1>
      <.link
        id="start-here"
        navigate={~p"/workflows"}
        class="inline-flex min-h-14 items-center justify-center rounded-md bg-gradient-to-r from-violet-800 to-sky-700 px-9 py-4 text-lg font-semibold text-white shadow-lg shadow-violet-500/20 transition duration-200 hover:from-violet-900 hover:to-sky-800 hover:shadow-xl focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-blue-600"
      >
        Start here
      </.link>
    </section>
    """
  end
end
