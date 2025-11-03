import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "checkbox",
    "panel",
    "count",
    "context",
    "results",
    "bulletsContent",
    "loading",
    "error",
    "errorMessage",
    "toggleButton"
  ]

  connect() {
    this.selectionMode = false
    this.selectedIds = new Set()
  }

  toggleSelection() {
    this.selectionMode = !this.selectionMode

    if (this.selectionMode) {
      // Show checkboxes
      this.checkboxTargets.forEach(cb => cb.classList.remove('hidden'))
      this.panelTarget.classList.remove('hidden')
      this.toggleButtonTarget.textContent = "Cancel Selection"
      this.toggleButtonTarget.classList.remove('bg-purple-600', 'hover:bg-purple-700')
      this.toggleButtonTarget.classList.add('bg-gray-500', 'hover:bg-gray-600')
    } else {
      // Hide checkboxes and panel
      this.checkboxTargets.forEach(cb => {
        cb.classList.add('hidden')
        cb.checked = false
      })
      this.panelTarget.classList.add('hidden')
      this.toggleButtonTarget.textContent = "Generate CV Bullets"
      this.toggleButtonTarget.classList.remove('bg-gray-500', 'hover:bg-gray-600')
      this.toggleButtonTarget.classList.add('bg-purple-600', 'hover:bg-purple-700')
      this.selectedIds.clear()
      this.updateCount()
      this.hideResults()
    }
  }

  updateSelection(event) {
    const checkbox = event.target
    if (checkbox.checked) {
      this.selectedIds.add(checkbox.value)
    } else {
      this.selectedIds.delete(checkbox.value)
    }
    this.updateCount()
  }

  updateCount() {
    this.countTarget.textContent = this.selectedIds.size
  }

  cancel() {
    this.toggleSelection()
  }

  async generate() {
    if (this.selectedIds.size === 0) {
      this.showError("Please select at least one commit")
      return
    }

    this.hideResults()
    this.hideError()
    this.showLoading()

    try {
      const response = await fetch('/api/v1/commits/generate_cv_bullets', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({
          commit_ids: Array.from(this.selectedIds),
          context: this.contextTarget.value.trim() || null
        })
      })

      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.error || 'Failed to generate CV bullets')
      }

      const data = await response.json()
      this.showResults(data.bullets)
    } catch (error) {
      console.error('CV generation error:', error)
      this.showError(error.message)
    } finally {
      this.hideLoading()
    }
  }

  showLoading() {
    this.loadingTarget.classList.remove('hidden')
  }

  hideLoading() {
    this.loadingTarget.classList.add('hidden')
  }

  showResults(bullets) {
    this.bulletsContentTarget.textContent = bullets
    this.resultsTarget.classList.remove('hidden')
  }

  hideResults() {
    this.resultsTarget.classList.add('hidden')
  }

  showError(message) {
    this.errorMessageTarget.textContent = message
    this.errorTarget.classList.remove('hidden')
  }

  hideError() {
    this.errorTarget.classList.add('hidden')
  }

  async copyToClipboard() {
    const text = this.bulletsContentTarget.textContent
    try {
      await navigator.clipboard.writeText(text)
      // Show success feedback
      const originalText = event.target.textContent
      event.target.textContent = "Copied!"
      setTimeout(() => {
        event.target.textContent = originalText
      }, 2000)
    } catch (error) {
      console.error('Failed to copy:', error)
      this.showError('Failed to copy to clipboard')
    }
  }
}
