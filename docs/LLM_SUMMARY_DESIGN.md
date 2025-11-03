# LLM-Generated Business Value Summaries - Design Document

## Overview

CommitKit will enhance commits with AI-generated business value summaries, helping teams understand the impact of code changes in non-technical terms. This feature supports both server-side processing (we manage the LLM) and BYOK (Bring Your Own Key) for users who prefer to use their own LLM API keys.

## Core Design Principles

1. **Optional** - AI summaries are opt-in, not required
2. **Flexible** - Support both server-side and client-side (BYOK) processing
3. **Fast** - Don't slow down commits (async processing where possible)
4. **Cost-aware** - Users control costs with BYOK or rate-limited free tier
5. **Privacy-conscious** - Support local processing for sensitive codebases

---

## Technical Architecture

### Hybrid Approach: Server + Client Options

We support three modes:

**1. Server Mode (Default)**
- Server generates summaries using CommitKit's LLM API keys
- Fast commits (no CLI waiting)
- Background job processing
- Rate-limited for cost control
- Works with commit message only (no diff access)

**2. Client Mode (BYOK)**
- CLI generates summaries using user's LLM API key
- Has full diff access (more context = better summaries)
- User pays LLM costs directly
- Commits slightly slower (wait for LLM)
- Maximum privacy (diffs never leave user's machine)

**3. Off Mode**
- No AI summaries generated
- Fastest commits
- No costs

---

## Database Schema

### Migration: Add AI Summary Fields

```ruby
class AddAiSummaryToCommits < ActiveRecord::Migration[8.1]
  def change
    add_column :commits, :ai_summary, :text
    add_column :commits, :ai_provider, :string
    add_column :commits, :ai_model, :string
    add_column :commits, :ai_generated_at, :datetime
    add_column :commits, :ai_processing_status, :string, default: "pending"
    add_column :commits, :ai_summary_original, :text  # Backup for conflict detection

    add_index :commits, :ai_processing_status
    add_index :commits, [:user_id, :ai_processing_status]
  end
end
```

**Field Descriptions:**
- `ai_summary` - The generated business value summary
- `ai_provider` - "anthropic", "openai", "server", etc.
- `ai_model` - Specific model version (e.g., "claude-3-5-sonnet-20241022")
- `ai_generated_at` - Timestamp of generation
- `ai_processing_status` - Lifecycle: "pending", "processing", "completed", "failed", "skipped"
- `ai_summary_original` - Original AI summary (before user edits) for conflict detection

### User Settings

```ruby
class AddLlmSettingsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :llm_mode, :string, default: "off"  # off, server, client
    add_column :users, :llm_daily_limit, :integer, default: 10
    add_column :users, :llm_summaries_today, :integer, default: 0
    add_column :users, :llm_summaries_reset_at, :date
  end
end
```

---

## API Changes

### Update Existing Endpoint

```ruby
POST /api/v1/repositories
Body: {
  "url": "https://github.com/user/repo.git",
  "commits": [
    {
      "commit_hash": "abc123",
      "message": "Add payment processing",
      "summary": "Enable credit card payments",
      "committed_at": "2025-11-03T10:00:00Z",

      # New: AI summary fields (optional)
      "ai_summary": "Business value: Enables revenue generation through...",
      "ai_provider": "anthropic",
      "ai_model": "claude-3-5-sonnet-20241022"
    }
  ],
  "sync_mode": "replace"
}
```

**Behavior:**
- If `ai_summary` present: store it (client-generated)
- If `ai_summary` absent and user has server mode enabled: enqueue background job
- If user has AI disabled: skip processing

### New Endpoint: Batch Regenerate

```ruby
POST /api/v1/repositories/:id/regenerate_ai_summaries
Body: {
  "commit_hashes": ["abc123", "def456"],  # Optional: specific commits
  "force": false  # Overwrite existing summaries
}

Response: {
  "queued": 50,
  "skipped": 10,  # Already have summaries and force=false
  "message": "AI summary generation queued for 50 commits"
}
```

---

## Configuration

### CLI Config File (~/.commitkit/config.yml)

```yaml
llm:
  mode: "off"  # off, server, client

  # Client-side config (BYOK)
  provider: "anthropic"  # anthropic, openai, gemini
  api_key_ref: "keychain:commitkit_llm_api_key"  # Reference to keychain
  model: "claude-3-5-sonnet-20241022"

  # Cost controls
  max_commits_per_day: 50
  confirm_expensive_commits: true  # Prompt if commit > 10KB

  # Behavior
  async: false  # Wait for AI summary or send async?
  timeout_seconds: 10
  retry_on_failure: true

  # Privacy
  secret_detection: true  # Scan for secrets before sending diff
  max_diff_size_kb: 10
```

### CLI Config Commands

```bash
# View current config
commitkit config get llm

# Set mode
commitkit config set llm.mode [off|server|client]

# Client mode setup
commitkit config set llm.provider anthropic
commitkit config set llm.api_key sk-ant-...  # Stored in keychain
commitkit config set llm.model claude-3-5-sonnet-20241022

# Cost controls
commitkit config set llm.max_commits_per_day 50

# Test connection
commitkit llm test

# Show usage stats
commitkit llm usage
# Output:
# This month (November 2025):
# - AI summaries generated: 45
# - Estimated cost: $0.45 USD
# - Remaining today: 5/50
```

---

## User Flows

### Flow 1: Enable Server-Side AI (Default)

```bash
# User enables AI summaries (server-side)
$ commitkit config set llm.mode server

✓ Server-side AI summaries enabled
  - Free tier: 10 summaries/day
  - Summaries generated in background
  - View on dashboard: https://commitkit.app/dashboard

# Make a commit (fast - no waiting)
$ git commit -m "Fix checkout bug"
[main abc123] Fix checkout bug
✓ Synced to CommitKit
💡 AI summary will be generated shortly

# View on dashboard
$ open https://commitkit.app/dashboard
# Shows: "Processing..." then updates to full summary
```

### Flow 2: Enable BYOK (Client-Side)

```bash
# User sets up their own API key
$ commitkit config set llm.mode client
$ commitkit config set llm.provider anthropic
$ commitkit config set llm.api_key sk-ant-api03-...

✓ Client-side AI summaries enabled
  - Using your Anthropic API key
  - Estimated cost: ~$0.01 per commit
  - Summaries generated immediately

# Make a commit (waits for AI)
$ git commit -m "Add payment processing"
[main def456] Add payment processing
⏳ Generating business value summary...
✓ AI summary generated (0.8s)
✓ Synced to CommitKit

# Summary is already on server
```

### Flow 3: Resync Existing Commits with AI

```bash
# User has 500 existing commits without AI summaries
$ commitkit resync --with-ai

This will generate AI summaries for 500 commits.
Mode: client (using your Anthropic API key)
Estimated cost: ~$5.00 USD
Estimated time: ~8 minutes

Continue? (y/N) y

[██████████░░░░░░░░░░] 50% (250/500) - 4 min remaining
✓ Generated 250 AI summaries
✓ Synced to CommitKit

[████████████████████] 100% (500/500)
✓ Complete! Generated 500 AI summaries
  - Cost: $4.87 USD
  - Time: 7m 32s
  - View on dashboard: https://commitkit.app/dashboard
```

### Flow 4: Regenerate Single Summary

```bash
# From dashboard: click "Regenerate" on a bad summary
# Or from CLI:
$ commitkit llm regenerate abc123

Regenerating AI summary for commit abc123...
✓ Done
New summary: "Reduces customer churn by 15% by fixing critical..."
```

### Flow 5: Cost Limit Reached

```bash
# User hits daily limit
$ git commit -m "Add feature X"
[main ghi789] Add feature X

⚠️  Daily AI summary limit reached (50/50)
    Commit synced without AI summary.

Options:
  1. Wait until tomorrow (limit resets at midnight UTC)
  2. Disable limit: commitkit config set llm.max_commits_per_day 0
  3. Upgrade to Pro for unlimited summaries

💡 Run 'commitkit llm usage' to see stats
```

---

## LLM Prompts

### Client-Side Prompt (with diff)

```
You are analyzing a git commit to extract business value.

COMMIT MESSAGE:
{commit.message}

FILE CHANGES:
{commit.files_changed}

COMMIT DIFF (first 10KB):
{commit.diff_truncated}

INSTRUCTIONS:
Generate a 1-2 sentence summary of the business value this commit provides.

Focus on:
- What problem it solves for users or the business
- Quantifiable impact (revenue, performance, support tickets, user satisfaction)
- Who benefits (customers, internal teams, stakeholders)

Rules:
- Write for a non-technical audience (product managers, executives)
- Be specific and concrete, not generic
- Avoid technical jargon
- If impact is unclear, focus on what changed and why it matters

GOOD EXAMPLES:
- "Reduces customer support tickets by 30% by fixing the checkout bug that caused payment failures. Estimated revenue recovery: $10K/month."
- "Improves page load time from 3s to 800ms, reducing bounce rate and increasing conversion by 12% based on A/B test data."
- "Enables sales team to close enterprise deals by adding SSO support, a blocker for 5 Fortune 500 prospects."

BAD EXAMPLES:
- "Fixed a bug" (too vague)
- "Refactored the UserService class to use dependency injection" (too technical)
- "Made improvements" (meaningless)

YOUR SUMMARY (1-2 sentences):
```

### Server-Side Prompt (message only)

```
You are analyzing a git commit message to extract business value.

COMMIT MESSAGE:
{commit.message}

INSTRUCTIONS:
Generate a 1-2 sentence summary of the likely business value this commit provides.

Note: You only have the commit message, not the code changes. Make reasonable inferences based on the message.

Focus on:
- What problem it likely solves
- Potential business impact (revenue, performance, user experience)
- Who might benefit

Rules:
- Write for a non-technical audience
- Be specific but acknowledge uncertainty when appropriate
- Avoid technical jargon
- If message is too vague, focus on the category of change (feature, bugfix, performance)

GOOD EXAMPLES:
- "Likely reduces payment failures and increases completed transactions by fixing checkout flow issues. Impact depends on severity of bug."
- "Improves user retention by adding requested feature for profile customization. Common request from feedback surveys."
- "Enables team to ship features faster by improving CI/CD pipeline, reducing deploy time from 20 to 5 minutes."

YOUR SUMMARY (1-2 sentences):
```

**Prompt Versioning:**
- Store prompt template in database
- Version field: `prompt_version: "v1"`
- Track which prompt version generated each summary
- Allows A/B testing and iteration

---

## CLI Implementation

### Post-Commit Hook

```ruby
# lib/commitkit/hooks/post_commit.rb
class PostCommitHook
  def execute(commit)
    # Always sync commit metadata
    api.sync_commit(commit)

    # Generate AI summary if enabled
    if config.llm_mode == "client"
      generate_client_side_summary(commit)
    end
    # Server mode: API handles it in background
  end

  def generate_client_side_summary(commit)
    # Check daily limit
    if over_daily_limit?
      warn_limit_reached
      return
    end

    # Prepare data
    diff = prepare_diff(commit)
    prompt = build_prompt(commit, diff)

    # Call LLM
    summary = llm_provider.complete(prompt)

    # Update on server
    api.update_commit_ai_summary(
      commit_hash: commit.hash,
      ai_summary: summary,
      ai_provider: config.llm_provider,
      ai_model: config.llm_model
    )

    # Track usage
    increment_daily_usage

    puts "✓ AI summary generated (#{duration}s)"
  rescue LLMError => e
    warn "⚠️  AI summary generation failed: #{e.message}"
    warn "    Commit synced without summary."
    # Don't block commit
  end

  def prepare_diff(commit)
    diff = commit.diff

    # Secret detection
    if config.secret_detection && has_secrets?(diff)
      raise LLMError, "Secrets detected in diff. AI summary disabled for safety."
    end

    # Size limit
    max_size = config.max_diff_size_kb * 1024
    if diff.bytesize > max_size
      diff = diff[0...max_size] + "\n\n[...truncated to #{config.max_diff_size_kb}KB...]"
    end

    diff
  end
end
```

### LLM Provider Abstraction

```ruby
# lib/commitkit/llm/provider.rb
module CommitKit
  module LLM
    class Provider
      def self.create(provider:, api_key:, model:)
        case provider.to_s
        when "anthropic"
          AnthropicProvider.new(api_key, model)
        when "openai"
          OpenAIProvider.new(api_key, model)
        when "gemini"
          GeminiProvider.new(api_key, model)
        else
          raise "Unsupported provider: #{provider}"
        end
      end
    end

    class AnthropicProvider
      def initialize(api_key, model)
        @client = Anthropic::Client.new(api_key: api_key)
        @model = model
      end

      def complete(prompt, timeout: 10)
        Timeout.timeout(timeout) do
          response = @client.messages(
            model: @model,
            max_tokens: 300,
            messages: [{ role: "user", content: prompt }]
          )
          response.dig("content", 0, "text")
        end
      rescue Timeout::Error
        raise LLMError, "LLM request timed out after #{timeout}s"
      rescue => e
        raise LLMError, "LLM request failed: #{e.message}"
      end
    end

    # Similar for OpenAIProvider, GeminiProvider...
  end
end
```

### Resync Command

```ruby
# lib/commitkit/commands/resync.rb
class ResyncCommand
  def execute(with_ai: false, force: false, limit: nil)
    commits = load_commits_from_git(limit: limit)

    if with_ai
      show_cost_estimate(commits.size)
      confirm_or_exit

      progress_bar = ProgressBar.new(commits.size)

      commits.each do |commit|
        generate_and_sync_ai_summary(commit, force: force)
        progress_bar.increment

        # Checkpoint every 50
        save_checkpoint if commits_processed % 50 == 0
      end

      show_summary(commits.size)
    else
      sync_without_ai(commits)
    end
  end

  def show_cost_estimate(count)
    cost_per_commit = 0.01  # Estimate
    total_cost = count * cost_per_commit
    duration = count * 1  # 1 second per commit

    puts "\nThis will generate AI summaries for #{count} commits."
    puts "Mode: #{config.llm_mode}"
    puts "Provider: #{config.llm_provider}" if config.llm_mode == "client"
    puts "Estimated cost: ~$#{sprintf('%.2f', total_cost)} USD"
    puts "Estimated time: ~#{duration_to_human(duration)}"
    puts ""
  end
end
```

---

## Server-Side Implementation

### Background Job

```ruby
# app/jobs/generate_ai_summary_job.rb
class GenerateAiSummaryJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(commit_id)
    commit = Commit.find(commit_id)
    return if commit.ai_processing_status == "completed"

    commit.update!(ai_processing_status: "processing")

    summary = LLMService.generate_summary(
      message: commit.message,
      provider: "anthropic",
      model: "claude-3-5-haiku-20241022"  # Cheaper model for server-side
    )

    commit.update!(
      ai_summary: summary,
      ai_summary_original: summary,
      ai_provider: "server",
      ai_model: "claude-3-5-haiku-20241022",
      ai_generated_at: Time.current,
      ai_processing_status: "completed"
    )
  rescue => e
    commit.update!(ai_processing_status: "failed")
    Rails.logger.error("AI summary generation failed for commit #{commit.id}: #{e.message}")
    Rollbar.error(e, commit_id: commit.id)
    raise  # Allow retry
  end
end
```

### LLM Service

```ruby
# app/services/llm_service.rb
class LLMService
  CACHE_TTL = 30.days

  def self.generate_summary(message:, provider:, model:)
    # Check cache first (dedupe identical messages)
    cache_key = "llm_summary:#{provider}:#{model}:#{Digest::SHA256.hexdigest(message)}"
    cached = Rails.cache.read(cache_key)
    return cached if cached

    # Generate new summary
    prompt = build_prompt(message)
    summary = call_llm(prompt, provider: provider, model: model)

    # Cache it
    Rails.cache.write(cache_key, summary, expires_in: CACHE_TTL)

    summary
  end

  def self.call_llm(prompt, provider:, model:)
    case provider
    when "anthropic"
      call_anthropic(prompt, model)
    else
      raise "Unsupported provider: #{provider}"
    end
  end

  def self.call_anthropic(prompt, model)
    client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])

    response = client.messages(
      model: model,
      max_tokens: 300,
      messages: [{ role: "user", content: prompt }],
      temperature: 0.7
    )

    response.dig("content", 0, "text")
  end

  private

  def self.build_prompt(message)
    # Use server-side prompt template
    PromptTemplate.find_by(name: "server_summary", version: "v1").render(message: message)
  end
end
```

### Rate Limiting

```ruby
# app/models/user.rb
class User < ApplicationRecord
  def can_generate_ai_summary?
    return true if pro_plan?  # Unlimited for Pro

    # Reset counter if new day
    reset_daily_limit_if_needed

    llm_summaries_today < llm_daily_limit
  end

  def increment_ai_summary_count
    reset_daily_limit_if_needed
    increment!(:llm_summaries_today)
  end

  private

  def reset_daily_limit_if_needed
    if llm_summaries_reset_at != Date.current
      update!(
        llm_summaries_today: 0,
        llm_summaries_reset_at: Date.current
      )
    end
  end
end
```

### Auto-Trigger on Commit

```ruby
# app/models/commit.rb
class Commit < ApplicationRecord
  after_create :enqueue_ai_summary, if: :should_generate_ai_summary?

  private

  def should_generate_ai_summary?
    user.llm_mode == "server" &&
      ai_summary.blank? &&
      user.can_generate_ai_summary?
  end

  def enqueue_ai_summary
    user.increment_ai_summary_count
    GenerateAiSummaryJob.perform_later(id)
  end
end
```

---

## Dashboard Updates

### Display AI Summary

```erb
<!-- app/views/dashboard/index.html.erb -->
<% @commits.each do |commit| %>
  <div class="commit-card">
    <!-- Commit header -->
    <div class="commit-header">
      <h3><%= commit.message.lines.first&.strip %></h3>
      <div class="commit-meta">
        <span class="text-muted"><%= time_ago_in_words(commit.committed_at) %> ago</span>
        <code><%= commit.commit_hash.truncate(12) %></code>
      </div>
    </div>

    <!-- AI Summary -->
    <% if commit.ai_summary.present? %>
      <div class="ai-summary <%= 'user-edited' if commit.ai_summary != commit.ai_summary_original %>">
        <div class="ai-summary-header">
          <span class="badge badge-ai">
            <i class="icon-sparkles"></i> AI Summary
          </span>
          <span class="text-muted small">
            by <%= commit.ai_provider %> (<%= commit.ai_model %>)
          </span>
        </div>

        <p class="ai-summary-text"><%= commit.ai_summary %></p>

        <div class="ai-summary-actions">
          <!-- User feedback -->
          <div class="feedback-buttons">
            <span class="text-muted">Was this helpful?</span>
            <%= link_to ai_summary_feedback_path(commit, rating: "up"),
                        method: :post,
                        class: "btn-feedback #{commit.ai_feedback == 'up' ? 'active' : ''}" do %>
              👍 <span class="count"><%= commit.ai_feedback_up_count %></span>
            <% end %>
            <%= link_to ai_summary_feedback_path(commit, rating: "down"),
                        method: :post,
                        class: "btn-feedback #{commit.ai_feedback == 'down' ? 'active' : ''}" do %>
              👎 <span class="count"><%= commit.ai_feedback_down_count %></span>
            <% end %>
          </div>

          <!-- Actions -->
          <%= link_to "Edit", edit_ai_summary_path(commit), class: "btn-link" %>
          <%= link_to "Regenerate", regenerate_ai_summary_path(commit),
                      method: :post,
                      data: { confirm: "Regenerate AI summary?" },
                      class: "btn-link" %>
        </div>
      </div>

    <% elsif commit.ai_processing_status == "processing" %>
      <div class="ai-summary processing">
        <div class="ai-summary-header">
          <span class="badge badge-processing">
            <i class="icon-spinner spinning"></i> Processing...
          </span>
        </div>
        <p class="text-muted">AI summary is being generated</p>
      </div>

    <% elsif commit.ai_processing_status == "failed" %>
      <div class="ai-summary failed">
        <div class="ai-summary-header">
          <span class="badge badge-error">
            <i class="icon-warning"></i> Generation Failed
          </span>
        </div>
        <p class="text-muted">Failed to generate AI summary</p>
        <%= link_to "Retry", regenerate_ai_summary_path(commit),
                    method: :post,
                    class: "btn-link" %>
      </div>

    <% elsif current_user.llm_mode != "off" %>
      <div class="ai-summary empty">
        <p class="text-muted">No AI summary yet</p>
        <%= link_to "Generate", generate_ai_summary_path(commit),
                    method: :post,
                    class: "btn-link" %>
      </div>
    <% end %>

    <!-- Rest of commit card... -->
  </div>
<% end %>
```

### Bulk Actions Banner

```erb
<% if @commits_without_ai.any? && current_user.llm_mode != "off" %>
  <div class="alert alert-info">
    <i class="icon-sparkles"></i>
    <strong><%= pluralize(@commits_without_ai.count, 'commit') %></strong>
    don't have AI summaries yet.

    <%= link_to "Generate AI summaries",
                bulk_generate_ai_summaries_path(repository_id: params[:repository_id]),
                method: :post,
                data: {
                  confirm: "Generate AI summaries for #{@commits_without_ai.count} commits? This will use your #{current_user.llm_mode} mode settings.",
                  disable_with: "Generating..."
                },
                class: "btn btn-primary btn-sm" %>
  </div>
<% end %>
```

### Settings Page

```erb
<!-- app/views/settings/edit.html.erb -->
<section class="settings-section">
  <h2>AI Summary Settings</h2>

  <%= form_with model: @user, url: settings_path do |f| %>
    <div class="form-group">
      <%= f.label :llm_mode, "AI Summary Mode" %>
      <%= f.select :llm_mode,
                   [
                     ["Off - No AI summaries", "off"],
                     ["Server - We generate summaries (free tier: 10/day)", "server"],
                     ["Client (BYOK) - Use your own API key", "client"]
                   ],
                   {},
                   class: "form-control" %>
      <small class="form-text text-muted">
        Control how AI summaries are generated for your commits.
      </small>
    </div>

    <% if @user.llm_mode == "server" %>
      <div class="alert alert-info">
        <p><strong>Server Mode:</strong> We generate AI summaries using our LLM API keys.</p>
        <ul>
          <li>Free tier: <%= @user.llm_daily_limit %> summaries per day</li>
          <li>Today's usage: <%= @user.llm_summaries_today %>/<%= @user.llm_daily_limit %></li>
          <li>Resets: <%= @user.llm_summaries_reset_at || "Tonight at midnight UTC" %></li>
        </ul>

        <% unless @user.pro_plan? %>
          <p>
            <%= link_to "Upgrade to Pro", pricing_path, class: "btn btn-primary btn-sm" %>
            for unlimited AI summaries
          </p>
        <% end %>
      </div>
    <% end %>

    <% if @user.llm_mode == "client" %>
      <div class="alert alert-warning">
        <p><strong>Client Mode (BYOK):</strong> Configure in CLI:</p>
        <pre>commitkit config set llm.provider anthropic
commitkit config set llm.api_key sk-ant-...
commitkit config set llm.model claude-3-5-sonnet-20241022</pre>

        <p>
          <strong>Privacy:</strong> Your diffs are sent to your chosen LLM provider,
          not to CommitKit servers.
        </p>
        <p>
          <strong>Cost:</strong> ~$0.01 per commit (you pay your LLM provider directly)
        </p>
      </div>
    <% end %>

    <%= f.submit "Save Settings", class: "btn btn-primary" %>
  <% end %>
</section>
```

---

## Edge Cases & Mitigations

### 1. Cost Control (BYOK)

**Risk:** User's LLM bill explodes with frequent commits

**Mitigations:**
- Default daily limit: 50 commits
- Warning when approaching: "45/50 AI summaries used today"
- Cost tracking: `~/.commitkit/usage.json`
- Monthly summary: `commitkit llm usage --month november`
- Large diff warning: "This commit is 50KB. Estimated cost: $0.05. Continue? (y/N)"

**Implementation:**
```ruby
def check_cost_before_generation(commit)
  usage = UsageTracker.load

  if usage.summaries_today >= config.max_commits_per_day
    raise LimitError, "Daily limit reached (#{usage.summaries_today}/#{config.max_commits_per_day})"
  end

  estimated_cost = estimate_cost(commit)
  if estimated_cost > 0.05 && config.confirm_expensive_commits
    puts "⚠️  This commit is large. Estimated cost: $#{sprintf('%.2f', estimated_cost)}"
    print "Continue? (y/N) "
    exit unless STDIN.gets.chomp.downcase == 'y'
  end
end
```

### 2. LLM API Failures

**Risk:** Commits blocked by LLM downtime

**Mitigations:**
- **Timeout:** 10 seconds max
- **Retry:** 1 automatic retry with 2s delay
- **Fallback:** Sync commit without AI summary (don't block)
- **User feedback:** Clear error messages
- **Async mode:** Optional config to generate summaries after commit completes

**Implementation:**
```ruby
def generate_with_fallback(commit)
  begin
    Timeout.timeout(10) do
      summary = llm_provider.complete(prompt)
      return summary
    end
  rescue Timeout::Error
    warn "⚠️  LLM request timed out. Retrying once..."
    sleep 2
    retry_once
  rescue LLMError => e
    warn "⚠️  AI summary generation failed: #{e.message}"
    warn "    Commit synced without summary."
    nil  # Graceful degradation
  end
end
```

### 3. API Key Security

**Risk:** API keys leaked or stolen

**Mitigations:**
- **Keychain storage:** Use OS keychain (macOS Keychain, Windows Credential Manager)
- **File permissions:** `~/.commitkit/config.yml` is 0600
- **Never log keys:** Sanitize logs
- **Rotation:** `commitkit config rotate llm.api_key`
- **Leak detection:** Warn if key pattern appears in commit messages

**Implementation:**
```ruby
# Use macOS Keychain
require 'security'

def store_api_key(key)
  Security::InternetPassword.add(
    "commitkit-llm",
    "api-key",
    key
  )
end

def retrieve_api_key
  Security::InternetPassword.find(
    service: "commitkit-llm",
    account: "api-key"
  ).password
rescue
  raise ConfigError, "API key not found in keychain. Run: commitkit config set llm.api_key"
end
```

### 4. Diff Privacy (Secrets in Code)

**Risk:** Diffs contain secrets (API keys, passwords) sent to LLM

**Mitigations:**
- **Secret detection:** Scan diffs before sending
- **Redaction:** Replace detected secrets with `[REDACTED]`
- **User warning:** "Secrets detected. AI summary disabled."
- **Opt-out:** `git commit --no-verify` or `commitkit.skip-ai: true` in commit message
- **Patterns:** Detect common secret patterns (AWS keys, tokens, etc.)

**Implementation:**
```ruby
SECRET_PATTERNS = [
  /AKIA[0-9A-Z]{16}/,  # AWS Access Key
  /sk-[a-zA-Z0-9]{48}/,  # Anthropic API key
  /sk-[a-zA-Z0-9-]{32,}/,  # OpenAI API key
  /ghp_[a-zA-Z0-9]{36}/,  # GitHub PAT
  /password\s*=\s*["'][^"']+["']/i,
  /api[_-]?key\s*=\s*["'][^"']+["']/i
].freeze

def has_secrets?(diff)
  SECRET_PATTERNS.any? { |pattern| diff.match?(pattern) }
end

def safe_diff(commit)
  diff = commit.diff

  if has_secrets?(diff)
    warn "⚠️  Secrets detected in commit diff!"
    warn "    AI summary generation disabled for safety."
    warn "    Remove secrets from code before committing."
    raise SecretDetectedError
  end

  diff
end
```

### 5. Large Diffs

**Risk:** Huge diffs (1000+ lines) are slow/expensive to process

**Mitigations:**
- **Size limit:** 10KB max diff sent to LLM
- **Truncation:** "...[truncated to 10KB]..."
- **Cost estimate:** Warn before processing large diffs
- **Smart truncation:** Keep beginning and end, truncate middle
- **File list:** If diff too large, send file list + message instead

**Implementation:**
```ruby
MAX_DIFF_SIZE = 10 * 1024  # 10KB

def prepare_diff_for_llm(commit)
  diff = commit.diff

  if diff.bytesize > MAX_DIFF_SIZE
    # Show warning
    estimated_cost = (diff.bytesize / 1024.0) * 0.001  # Rough estimate
    warn "⚠️  Large commit detected (#{diff.bytesize / 1024}KB)"
    warn "    Estimated cost: $#{sprintf('%.3f', estimated_cost)}"

    if config.confirm_expensive_commits
      print "Continue? (y/N) "
      exit unless STDIN.gets.chomp.downcase == 'y'
    end

    # Truncate intelligently
    diff = smart_truncate(diff, MAX_DIFF_SIZE)
  end

  diff
end

def smart_truncate(diff, max_size)
  return diff if diff.bytesize <= max_size

  # Keep first 40% and last 40%, truncate middle 20%
  first_chunk = max_size * 0.4
  last_chunk = max_size * 0.4

  beginning = diff[0...first_chunk.to_i]
  ending = diff[-last_chunk.to_i..-1]

  "#{beginning}\n\n[...#{(diff.bytesize - max_size) / 1024}KB truncated...]\n\n#{ending}"
end
```

### 6. Stale Summaries After Rebase/Amend

**Risk:** User rebases commit, AI summary no longer accurate

**Mitigations:**
- **Track commit hash:** If hash changes, mark summary as stale
- **Show warning:** "This commit was rebased. AI summary may be outdated."
- **Regenerate prompt:** "Regenerate summary for updated commit?"
- **Low priority:** Most users don't rebase after syncing

**Implementation:**
```ruby
# When commit hash changes
def detect_rebase
  existing = Commit.find_by(
    repository_id: repo.id,
    message: commit.message  # Same message, different hash
  )

  if existing && existing.commit_hash != commit.hash
    existing.update!(
      ai_summary_stale: true,
      ai_stale_reason: "Commit rebased (old hash: #{existing.commit_hash})"
    )
  end
end
```

### 7. Rate Limiting (Server-Side)

**Risk:** Server LLM costs spiral out of control

**Mitigations:**
- **Per-user limits:** Free tier 10/day, Pro unlimited
- **Global limits:** Max 10,000 summaries/hour across all users
- **Cost tracking:** Monitor spend per user/day
- **Cache hits:** Dedupe identical commit messages
- **Model choice:** Use cheaper model (Haiku) for server-side

**Pricing tiers:**
```
Free:
- 10 AI summaries per day (server-side)
- Basic features

Pro ($9/month):
- Unlimited AI summaries (server-side)
- OR use your own API key (BYOK) for unlimited
- Priority processing
- Custom prompts

Enterprise:
- Custom pricing
- Dedicated LLM resources
- Custom model fine-tuning
```

### 8. Multi-Provider Complexity

**Risk:** Supporting many LLM providers is maintenance burden

**Mitigations:**
- **Start small:** Launch with Anthropic only (Phase 1)
- **Add incrementally:** OpenAI in Phase 2, others on demand
- **Adapter pattern:** Clean abstraction for providers
- **Test coverage:** Integration tests for each provider
- **Fallback:** If primary provider fails, try secondary

**Provider priority:**
```ruby
PROVIDER_PRIORITY = [
  "anthropic",  # Best quality for our use case
  "openai",     # Most popular
  "gemini"      # Google's offering
].freeze

def call_with_fallback(prompt)
  PROVIDER_PRIORITY.each do |provider|
    begin
      return call_provider(provider, prompt)
    rescue ProviderError => e
      warn "Provider #{provider} failed: #{e.message}"
      next  # Try next provider
    end
  end

  raise "All LLM providers failed"
end
```

### 9. Summary Quality Issues

**Risk:** Summaries are generic, unhelpful, or wrong

**Mitigations:**
- **Feedback loop:** 👍👎 on each summary
- **A/B testing:** Test prompt variations
- **Examples in prompt:** Show good/bad examples
- **Temperature:** Use 0.7 for consistent but varied output
- **Regenerate:** Easy button to try again
- **Manual edit:** Allow users to override bad summaries

**Track quality:**
```ruby
# app/models/commit.rb
has_many :ai_summary_feedbacks

def ai_feedback_score
  up_votes = ai_summary_feedbacks.where(rating: "up").count
  down_votes = ai_summary_feedbacks.where(rating: "down").count

  return 0 if (up_votes + down_votes).zero?

  (up_votes - down_votes).to_f / (up_votes + down_votes)
end

# Track in analytics
def self.average_ai_quality_score
  Commit.where.not(ai_summary: nil)
        .map(&:ai_feedback_score)
        .sum / count.to_f
end
```

---

## Implementation Phases

### Phase 1: Server-Side MVP (Recommended Start)

**Scope:**
- Server-side AI generation only
- Single provider (Anthropic Haiku for cost)
- Background job processing
- Dashboard display with processing status
- Manual regenerate button
- Basic rate limiting (10/day free tier)

**Why Phase 1:**
- Fastest to ship (2-3 days)
- Validate user demand
- No CLI complexity
- No API key management
- Easier to debug

**Deliverables:**
- ✅ Database migration (ai_summary fields)
- ✅ Background job (GenerateAiSummaryJob)
- ✅ LLM service (Anthropic integration)
- ✅ Dashboard UI (show summaries)
- ✅ Rate limiting (User model)
- ✅ Settings page (enable/disable)

**Effort:** 2-3 days

### Phase 2: BYOK (Client-Side)

**Scope:**
- CLI config for LLM API keys
- Client-side summary generation (has diff access)
- Support Anthropic + OpenAI providers
- Resync command (`--with-ai` flag)
- Cost tracking and warnings
- Usage reporting

**Deliverables:**
- ✅ CLI config commands
- ✅ LLM provider abstraction
- ✅ Post-commit hook (generate summaries)
- ✅ Resync command
- ✅ Cost tracking (local file)
- ✅ Secret detection
- ✅ Keychain integration

**Effort:** 1 week

### Phase 3: Advanced Features

**Scope:**
- User feedback (👍👎)
- Manual editing with conflict detection
- Custom prompt templates
- Multiple provider support (Gemini, etc.)
- Advanced cost controls
- A/B testing framework
- Quality analytics

**Deliverables:**
- ✅ Feedback system
- ✅ Edit AI summaries
- ✅ Custom prompts (user-defined)
- ✅ Provider fallbacks
- ✅ Analytics dashboard

**Effort:** 1-2 weeks

---

## Success Metrics

### Phase 1 Metrics
- **Adoption:** % of users who enable AI summaries
- **Generation rate:** Summaries generated per day
- **Quality:** 👍👎 ratio (target: >70% positive)
- **Cost:** Average LLM cost per user per month
- **Performance:** P95 latency for summary generation

### Phase 2 Metrics
- **BYOK adoption:** % of users using client mode vs server mode
- **Cost savings:** Reduced server LLM spend from BYOK users
- **Usage patterns:** Average summaries per user per day

### Phase 3 Metrics
- **User retention:** Do users with AI stay longer?
- **Feature usage:** Do users read/engage with summaries?
- **Quality improvement:** Summary quality over time (via feedback)

**Target Benchmarks:**
- >50% of Pro users enable AI summaries
- >70% positive feedback on summaries
- <$0.50 average server LLM cost per user per month
- >30% of power users adopt BYOK

---

## Open Questions

### 1. Should we support local LLMs (Ollama)?

**Pros:**
- Free for users
- Maximum privacy (nothing leaves machine)
- No API key management

**Cons:**
- Variable quality (model-dependent)
- Requires local setup (technical users only)
- Slower (no GPU acceleration for most users)
- Support burden (debugging local setups)

**Decision:** Defer to Phase 3 or later. Focus on cloud LLMs first.

---

### 2. Should AI summaries be editable on dashboard?

**Pros:**
- Users can fix bad summaries
- Improves quality over time
- Users feel in control

**Cons:**
- Conflicts with resync (which version wins?)
- Need to track original vs edited
- Complexity in CLI (how to know if edited?)

**Decision:** YES, but track both:
- `ai_summary` - Current (may be user-edited)
- `ai_summary_original` - Original AI output
- Show "edited" badge if different
- Resync warns before overwriting edits

---

### 3. Should we cache summaries for identical commit messages?

**Pros:**
- Saves cost (10-20% of commits are likely dupes)
- Faster processing
- Consistent output for same input

**Cons:**
- Less personalized (ignores repo context)
- Cache invalidation complexity
- Storage overhead

**Decision:** YES for server-side, cache for 30 days.
```ruby
cache_key = "llm_summary:#{provider}:#{model}:#{Digest::SHA256.hexdigest(message)}"
Rails.cache.fetch(cache_key, expires_in: 30.days) do
  llm_provider.complete(prompt)
end
```

---

### 4. Should CLI wait for AI summary or process async?

**Option A: Synchronous (wait)**
- Pro: Immediate feedback, summary uploaded with commit
- Con: Slower commits (1-2 seconds delay)

**Option B: Asynchronous (background)**
- Pro: Fast commits
- Con: Summary comes later, requires second API call

**Decision:** Make it configurable:
```yaml
llm:
  async: false  # Default: wait for summary
```

Power users who commit frequently can enable async mode.

---

### 5. How to handle multi-line commit messages?

Many commits have structure:
```
Short title

Longer description explaining what changed and why.

Can include multiple paragraphs.
```

**Options:**
1. Use full message as context
2. Use only title (first line)
3. Parse conventional commits format

**Decision:** Use full message, but prompt emphasizes extracting business value (not rehashing technical details).

---

### 6. Should we support per-repository prompts?

Some teams may want customized prompts:
- "Focus on security impact"
- "Always mention affected microservices"
- "Translate to Spanish"

**Decision:** Phase 3 feature. Start with global prompt, add per-repo customization later.

---

## Security & Privacy

### Data Flow (Client Mode)

```
User's Machine:
1. Git commit made
2. CLI reads commit + diff
3. CLI sends to user's chosen LLM (Anthropic/OpenAI/etc)
4. LLM returns summary
5. CLI sends to CommitKit API: {commit_hash, message, summary}

CommitKit Server:
6. Store summary in database
7. Display on dashboard

Note: Diff never reaches CommitKit in client mode
```

### Data Flow (Server Mode)

```
User's Machine:
1. Git commit made
2. CLI sends to CommitKit API: {commit_hash, message}

CommitKit Server:
3. Store commit in database
4. Background job sends message to Anthropic
5. Anthropic returns summary
6. Store summary in database
7. Display on dashboard

Note: Diff never leaves user's machine in server mode either
```

### Privacy Guarantees

**Client Mode:**
- ✅ Diffs sent only to user's chosen LLM
- ✅ CommitKit never sees diffs
- ✅ User controls which provider (data residency)

**Server Mode:**
- ✅ Diffs never sent anywhere
- ✅ Only commit messages sent to Anthropic
- ❌ Commit messages visible to Anthropic (per their privacy policy)

**Compliance:**
- GDPR: Users control their data
- SOC 2: Encrypt data in transit and at rest
- HIPAA: Don't commit PHI in messages (warn users)

---

## Cost Analysis

### Server-Side Costs (Anthropic Haiku)

**Per summary:**
- Input: ~500 tokens (commit message + prompt)
- Output: ~100 tokens (1-2 sentence summary)
- Total: ~600 tokens per summary
- Cost: ~$0.001 per summary

**Monthly costs:**
- 1,000 active users × 10 summaries/day = 10,000 summaries/day
- 10,000 × 30 days = 300,000 summaries/month
- 300,000 × $0.001 = $300/month

**With caching (20% hit rate):**
- Actual API calls: 240,000
- Cost: $240/month

**Break-even:**
- Need ~27 Pro users ($9/month) to break even
- Very achievable with freemium model

### Client-Side Costs (User Pays)

**Per summary (Claude Sonnet):**
- Input: ~2,000 tokens (message + 10KB diff + prompt)
- Output: ~100 tokens
- Total: ~2,100 tokens
- Cost: ~$0.01 per summary

**Monthly cost for power user:**
- 50 commits/day × 30 days = 1,500 commits/month
- 1,500 × $0.01 = $15/month (user pays Anthropic directly)

**This is why BYOK matters:**
- Power users can opt for client mode (costs them directly)
- Reduces our server costs
- Scales better

---

## Migration Path for Existing Users

### For Users With Existing Commits

```bash
# User has 500 commits already synced
$ commitkit config set llm.mode server

AI summaries enabled (server mode).
You have 500 existing commits without AI summaries.

Options:
  1. Generate summaries for all 500 commits now
  2. Generate summaries only for new commits
  3. Do nothing (you can generate later)

Your choice (1-3): 1

Queueing 500 commits for AI summary generation...
✓ Queued. Summaries will appear on dashboard within ~10 minutes.
```

**Background processing:**
- Batch job processes 500 commits
- Rate limited: 10 per second (to avoid overwhelming API)
- Updates dashboard in real-time via Turbo Streams
- Email when complete: "AI summaries generated for 500 commits"

---

## Related Documents

- [API Documentation](API.md)
- [CLI Command Reference](CLI_REFERENCE.md)
- [Architecture Overview](ARCHITECTURE.md)
- [Offline Queue Design](OFFLINE_QUEUE_DESIGN.md) _(shelved)_

---

**Document Version:** 1.0
**Last Updated:** 2025-11-03
**Authors:** Richie Thomas, Claude (Anthropic)
**Status:** Draft - Ready for Review
