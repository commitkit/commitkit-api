import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    // Show the first tab by default (CV tab)
    this.showTab("cv")
  }

  switch(event) {
    const tabName = event.currentTarget.dataset.tabName
    this.showTab(tabName)
  }

  showTab(tabName) {
    // Update tab buttons
    this.tabTargets.forEach(tab => {
      const isActive = tab.dataset.tabName === tabName

      if (isActive) {
        tab.classList.remove('border-transparent', 'text-gray-500', 'hover:text-gray-700', 'hover:border-gray-300')
        tab.classList.add('border-purple-600', 'text-purple-600')
      } else {
        tab.classList.remove('border-purple-600', 'text-purple-600')
        tab.classList.add('border-transparent', 'text-gray-500', 'hover:text-gray-700', 'hover:border-gray-300')
      }
    })

    // Update panels
    this.panelTargets.forEach(panel => {
      if (panel.dataset.tabName === tabName) {
        panel.classList.remove('hidden')
      } else {
        panel.classList.add('hidden')
      }
    })
  }
}
