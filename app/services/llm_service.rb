# frozen_string_literal: true

require "anthropic"

# Service for generating AI summaries and CV bullet points using LLMs
class LlmService
  CACHE_TTL = 30.days
  DEFAULT_MODEL = "claude-3-5-haiku-20241022"  # Cheaper model for server-side
  CV_MODEL = "claude-3-5-sonnet-20241022"  # Better quality for CV generation

  class LlmError < StandardError; end

  def self.generate_commit_summary(message:)
    cache_key = summary_cache_key(message)

    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      prompt = build_commit_summary_prompt(message)
      call_anthropic(prompt, model: DEFAULT_MODEL)
    end
  end

  def self.generate_cv_bullets(commits:, context: nil)
    # Don't cache CV bullets (each request is unique based on commit selection)
    prompt = build_cv_bullets_prompt(commits, context)
    call_anthropic(prompt, model: CV_MODEL, max_tokens: 1000)
  end

  def self.call_anthropic(prompt, model:, max_tokens: 300)
    response = Anthropic.messages.create(
      model: model,
      max_tokens: max_tokens,
      messages: [ { role: "user", content: prompt } ],
      temperature: 0.7
    )

    Rails.logger.info("Anthropic API response: #{response.inspect}")

    response.dig(:content, 0, :text)
  rescue StandardError => e
    Rails.logger.error("Anthropic API error: #{e.class} - #{e.message}")
    Rails.logger.error("Backtrace: #{e.backtrace.first(5).join("\n")}")
    raise LlmError, "Failed to generate AI response: #{e.message}"
  end

  # Build prompt for commit business value summary
  def self.build_commit_summary_prompt(message)
    <<~PROMPT
      You are analyzing a git commit message to extract useful information for a developer's portfolio/CV.

      COMMIT MESSAGE:
      #{message}

      INSTRUCTIONS:
      Generate a concise 1-2 sentence summary that captures:
      - The technical work done (features, fixes, improvements)
      - Technologies/tools involved (if mentioned)
      - Measurable impact or outcomes (performance, reliability, user experience)
      - Business context or problem solved

      CRITICAL RULES:
      1. ONLY state facts directly evident from the commit message
      2. If information is uncertain or not explicitly stated, DO NOT include it
      3. If the message is too vague, provide a minimal factual description
      4. Never invent metrics, technologies, or outcomes not mentioned in the message
      5. Write in a factual, professional tone suitable for a resume
      6. Avoid speculation - err on the side of saying less rather than making assumptions

      GOOD EXAMPLES (based on actual commit content):
      Message: "Optimize database queries in user dashboard, reducing load time from 2.3s to 450ms"
      → "Optimized database queries in user dashboard, achieving a 5x improvement in load time (2.3s to 450ms)."

      Message: "Fix null pointer exception in payment processing"
      → "Fixed null pointer exception in payment processing flow."

      Message: "Add user profile customization feature"
      → "Implemented user profile customization feature."

      BAD EXAMPLES (making unwarranted assumptions):
      Message: "Fix bug in checkout"
      ❌ "Fixed critical bug that was causing 30% of payments to fail" (inventing impact)
      ✓ "Fixed bug in checkout flow."

      Message: "Update dependencies"
      ❌ "Improved security and performance by updating dependencies" (assuming benefits)
      ✓ "Updated project dependencies."

      YOUR SUMMARY (1-2 sentences, stick to verifiable facts only, no commentary):
    PROMPT
  end

  # Build prompt for CV bullet points from multiple commits
  def self.build_cv_bullets_prompt(commits, context)
    commits_text = commits.map.with_index do |commit, i|
      date = commit.committed_at || commit.created_at
      "#{i + 1}. #{commit.message}\n   Hash: #{commit.commit_hash}\n   Date: #{date.strftime('%b %Y')}"
    end.join("\n\n")

    context_section = if context.present?
      "\nADDITIONAL CONTEXT PROVIDED BY USER:\n#{context}\n"
    else
      ""
    end

    <<~PROMPT
      You are a professional resume writer helping a software engineer create compelling CV bullet points.

      The engineer has selected these commits from their work:

      #{commits_text}
      #{context_section}

      INSTRUCTIONS:
      Generate 3-5 professional CV bullet points based on these commits.

      Each bullet point should:
      - Start with a strong action verb (e.g., "Architected", "Implemented", "Optimized", "Led")
      - Quantify impact when possible (e.g., "improved performance by 40%", "reduced costs by $50K/year")
      - Focus on business value and outcomes, not just technical tasks
      - Be written for a technical recruiter or hiring manager
      - Be concise (1-2 lines max)

      Format:
      - One bullet point per line
      - Start each with "•" or "-"
      - No numbering
      - No explanations, just the bullets

      GOOD EXAMPLES:
      • Architected and deployed microservices-based payment system processing $2M+ in monthly transactions with 99.9% uptime
      • Reduced page load time by 60% through React optimization and lazy loading, improving conversion rate by 12%
      • Led migration of legacy monolith to Kubernetes, cutting infrastructure costs by $40K annually while improving scalability

      BAD EXAMPLES:
      • Fixed bugs (too vague, no impact)
      • Worked on the codebase (no specific achievement)
      • Used React and TypeScript (just listing technologies)

      YOUR CV BULLET POINTS:
    PROMPT
  end

  # Generate cache key for commit summary
  def self.summary_cache_key(message)
    message_hash = Digest::SHA256.hexdigest(message)
    "llm_summary:#{DEFAULT_MODEL}:#{message_hash}"
  end

  private_class_method :call_anthropic,
                       :build_commit_summary_prompt,
                       :build_cv_bullets_prompt,
                       :summary_cache_key
end
