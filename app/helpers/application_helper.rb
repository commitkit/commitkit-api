module ApplicationHelper
  include Pagy::Frontend

  def pagy_tailwind_nav(pagy)
    html = +%(<nav class="flex items-center justify-center gap-1" aria-label="Pagination">)

    # Previous button
    if pagy.prev
      html << link_to("←", pagy_url_for(pagy, pagy.prev),
                     class: "px-3 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50",
                     aria_label: "Previous")
    else
      html << %(<span class="px-3 py-2 text-sm font-medium text-gray-400 bg-gray-100 border border-gray-300 rounded-md cursor-not-allowed">←</span>)
    end

    # Page numbers
    pagy.series.each do |item|
      case item
      when Integer
        if item == pagy.page
          html << %(<span class="px-3 py-2 text-sm font-medium text-blue-600 bg-blue-50 border border-blue-300 rounded-md">#{item}</span>)
        else
          html << link_to(item, pagy_url_for(pagy, item),
                         class: "px-3 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50")
        end
      when "gap"
        html << %(<span class="px-2 py-2 text-sm text-gray-400">...</span>)
      end
    end

    # Next button
    if pagy.next
      html << link_to("→", pagy_url_for(pagy, pagy.next),
                     class: "px-3 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50",
                     aria_label: "Next")
    else
      html << %(<span class="px-3 py-2 text-sm font-medium text-gray-400 bg-gray-100 border border-gray-300 rounded-md cursor-not-allowed">→</span>)
    end

    html << %(</nav>)
    html.html_safe
  end
end
