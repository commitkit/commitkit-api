import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "toggle"]
  static values = { lines: { type: Number, default: 3 } }

  connect() {
    this.checkHeight()
  }

  checkHeight() {
    const lineHeight = parseFloat(getComputedStyle(this.contentTarget).lineHeight)
    const maxHeight = lineHeight * this.linesValue
    const actualHeight = this.contentTarget.scrollHeight

    if (actualHeight > maxHeight) {
      this.contentTarget.style.maxHeight = `${maxHeight}px`
      this.contentTarget.style.overflow = "hidden"
      this.toggleTarget.classList.remove("hidden")
    } else {
      this.toggleTarget.classList.add("hidden")
    }
  }

  toggle() {
    const isExpanded = this.contentTarget.style.maxHeight === "none"

    if (isExpanded) {
      // Collapse
      const lineHeight = parseFloat(getComputedStyle(this.contentTarget).lineHeight)
      const maxHeight = lineHeight * this.linesValue
      this.contentTarget.style.maxHeight = `${maxHeight}px`
      this.contentTarget.style.overflow = "hidden"
      this.toggleTarget.textContent = "More..."
    } else {
      // Expand
      this.contentTarget.style.maxHeight = "none"
      this.contentTarget.style.overflow = "visible"
      this.toggleTarget.textContent = "Less"
    }
  }
}
