# frozen_string_literal: true

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
    client = Anthropic::Client.new(api_key: ENV.fetch("ANTHROPIC_API_KEY"))

    response = client.messages(
      model: model,
      max_tokens: max_tokens,
      messages: [{ role: "user", content: prompt }],
      temperature: 0.7
    )

    response.dig("content", 0, "text")
  rescue StandardError => e
    Rails.logger.error("Anthropic API error: #{e.message}")
    raise LlmError, "Failed to generate AI response: #{e.message}"
  end

  # Build prompt for commit business value summary
  def self.build_commit_summary_prompt(message)
    <<~PROMPT
      You are analyzing a git commit message to extract business value.

      COMMIT MESSAGE:
      #{message}

      INSTRUCTIONS:
      Generate a 1-2 sentence summary of the likely business value this commit provides.

      Note: You only have the commit message, not the code changes. Make reasonable inferences based on the message.

      Focus on:
      - What problem it likely solves
      - Potential business impact (revenue, performance, user experience)
      - Who might benefit (customers, internal teams, stakeholders)

      Rules:
      - Write for a non-technical audience (product managers, executives)
      - Be specific but acknowledge uncertainty when appropriate
      - Avoid technical jargon
      - If message is too vague, focus on the category of change (feature, bugfix, performance)

      GOOD EXAMPLES:
      - "Likely reduces payment failures and increases completed transactions by fixing checkout flow issues. Impact depends on severity of bug."
      - "Improves user retention by adding requested feature for profile customization. Common request from feedback surveys."
      - "Enables team to ship features faster by improving CI/CD pipeline, reducing deploy time from 20 to 5 minutes."

      YOUR SUMMARY (1-2 sentences):
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
