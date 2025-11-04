import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    count: Number
  }

  async generate() {
    const button = this.element
    const originalText = button.textContent

    // Disable button and show loading state
    button.disabled = true
    button.classList.add('opacity-75', 'cursor-not-allowed')
    button.innerHTML = `
      <span class="inline-flex items-center gap-2">
        <svg class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        Generating...
      </span>
    `

    try {
      const response = await fetch('/ai_summaries', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })

      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.error || 'Failed to generate AI summaries')
      }

      const data = await response.json()

      // Show success message
      button.innerHTML = `
        <span class="inline-flex items-center gap-2">
          <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
          </svg>
          Processing ${data.enqueued}...
        </span>
      `

      // Reload page after a delay to show updated summaries
      setTimeout(() => {
        window.location.reload()
      }, 3000)

    } catch (error) {
      console.error('AI generation error:', error)

      // Show error state
      button.classList.remove('bg-purple-600', 'hover:bg-purple-700')
      button.classList.add('bg-red-600')
      button.textContent = 'Failed - Try again'
      button.disabled = false
      button.classList.remove('opacity-75', 'cursor-not-allowed')

      // Reset after 3 seconds
      setTimeout(() => {
        button.classList.remove('bg-red-600')
        button.classList.add('bg-purple-600', 'hover:bg-purple-700')
        button.textContent = originalText
      }, 3000)
    }
  }
}
