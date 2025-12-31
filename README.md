# CommitKit API

Rails backend for CommitKit - automatically track git commits and generate professional CV/resume bullet points using AI.

## Overview

CommitKit helps developers turn their git commit history into polished resume bullet points. This Rails application provides:

- Web dashboard for viewing and managing tracked commits
- REST API for the CommitKit CLI to send commit data
- AI-powered commit summaries using Claude (Anthropic)
- Background job processing for async AI generation
- User authentication and API token management

**System Flow:**
```
Developer commits → CLI git hook → API endpoint → Database → AI job → Summary generated
```

## Tech Stack

- **Ruby:** 3.2.2
- **Rails:** 8.1.1
- **Database:** PostgreSQL
- **Background Jobs:** Solid Queue (Rails 8 built-in)
- **Authentication:** Rails 8 session-based + API Bearer tokens
- **CSS:** Tailwind CSS 4
- **AI:** Anthropic Claude API (`anthropic-rb` gem)
- **Deployment:** Render.com (Dockerized)

## Prerequisites

- Ruby 3.2.2 (use `rbenv` or `asdf`)
- PostgreSQL 14+
- Node.js (for Tailwind CSS compilation)
- Anthropic API key (for AI summaries)

## Installation

### Quick Setup

```bash
cd commitkit
bin/setup
```

This runs:
1. `bundle install` - Install gem dependencies
2. `bin/rails db:prepare` - Create and migrate database

After setup completes, start the server with `bin/dev`

### Manual Setup

```bash
# Install dependencies
bundle install

# Setup database
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed  # Optional: creates test data

# Setup environment variables (see below)
cp .env.example .env
# Edit .env with your ANTHROPIC_API_KEY

# Start server
bin/dev  # Runs Puma + Tailwind watcher
```

## Development

### Starting the Server

```bash
# Recommended: Runs Puma server + Tailwind CSS watcher
bin/dev

# Server only (localhost:3000)
bin/rails server

# Tailwind CSS commands
bin/rails tailwindcss:build   # One-time compile
bin/rails tailwindcss:watch   # Watch mode for development
```

**Important:** Always use `bin/dev` or run Tailwind separately - CSS won't update without it!

### Console

```bash
bin/rails console                      # Development console
bin/rails console --sandbox            # Auto-rollback on exit
RAILS_ENV=test bin/rails console       # Test environment
```

### Database

```bash
bin/rails db:migrate              # Run pending migrations
bin/rails db:rollback             # Rollback last migration
bin/rails db:reset                # Drop, create, migrate, seed
bin/rails db:test:prepare         # Prepare test database
```

## Testing

```bash
# Run all specs
bundle exec rspec

# By type
bundle exec rspec spec/models
bundle exec rspec spec/requests
bundle exec rspec spec/services

# Single file
bundle exec rspec spec/models/user_spec.rb

# Single test (by line number)
bundle exec rspec spec/models/user_spec.rb:42
```

**Test Coverage:**
- Model specs for validations and associations
- Request specs for all API endpoints
- Service specs for LLM integration
- Use FactoryBot: `create(:user)`, `create(:commit)`, etc.

## Architecture

### Dual Controller Pattern

**Web Controllers** (`app/controllers/`)
- Inherit from `ApplicationController < ActionController::Base`
- Session-based authentication
- Render ERB views
- Access user via `Current.user` (Rails 8 convention)

**API Controllers** (`app/controllers/api/v1/`)
- Inherit from `Api::V1::BaseController < ActionController::API`
- Bearer token authentication
- Return JSON responses
- Protected by `before_action :authenticate!`

### Data Models

```ruby
User
  has_many :repositories
  has_many :commits
  # Fields: email, password_digest, api_token, ai_summaries_enabled

Repository
  belongs_to :user
  has_many :commits
  # Fields: name, url, default_branch
  # Validations: url uniqueness per user

Commit
  belongs_to :user
  belongs_to :repository
  # Fields: commit_hash (unique!), message, timestamp
  # AI fields: ai_summary, ai_provider, ai_model, ai_processing_status
```

### AI Summary System

**LlmService** (`app/services/llm_service.rb`)
- Uses Anthropic Claude API
- Two models:
  - `claude-3-5-haiku-20241022`: Fast, cheap summaries (automatic background processing)
  - `claude-3-5-sonnet-20241022`: High-quality CV bullets (user-triggered generation)
- 30-day cache for commit summaries

**Background Processing:**
- `GenerateAiSummaryJob`: Async summary generation
- Enqueued automatically when commits created (if `ai_summaries_enabled`)
- Uses Solid Queue (Rails 8 built-in)

**Database Fields:**
- `ai_summary`: Generated business value text
- `ai_processing_status`: pending → processing → completed/failed
- `ai_generated_at`: Timestamp

## API Documentation

### Authentication

All API endpoints require Bearer token authentication:

```bash
Authorization: Bearer <user_api_token>
```

Get your token from the dashboard or generate via console:
```ruby
user = User.find_by(email: 'your@email.com')
user.api_token  # Use this in Authorization header
```

### Key Endpoints

**POST /api/v1/repositories**
- Batch upload commits for a repository
- Body: `{url: "repo-url", commits: [{commit_hash, message, timestamp}, ...]}`
- Returns: `{synced: 5, skipped: 2, failed: 0}`

**POST /api/v1/commits/generate_ai_summaries**
- Generate summaries for selected commits
- Body: `{commit_ids: [1, 2, 3]}`

**POST /api/v1/commits/generate_cv_bullets**
- Generate resume bullets from commits
- Body: `{commit_ids: [1, 2, 3]}`

**GET /up**
- Health check endpoint (public, no auth)
- Returns 200 OK if service is running

## Environment Variables

Create `.env` file (not committed to git):

```bash
# Required for AI summaries
ANTHROPIC_API_KEY=sk-ant-...

# Production only (set by Render)
DATABASE_URL=postgres://...
RAILS_MASTER_KEY=...  # For encrypted credentials
```

**Development:** Use `.env` file
**Production:** Set in Render.com dashboard

## Deployment

### Render.com (Production)

**Deployed to:** https://commitkit-api.onrender.com

**Dockerfile:** Located in monorepo root (`../Dockerfile`)

**Important: Free Tier Keep-Alive**

Render's free tier spins down after 15 minutes of inactivity. To prevent this:

1. **Use UptimeRobot** (free): https://uptimerobot.com/
2. Create monitor:
   - Type: **HTTP / website monitoring**
   - URL: `https://commitkit-api.onrender.com/up`
   - Interval: Every 5 minutes
   - Name: "CommitKit API"
3. Public status page: https://stats.uptimerobot.com/xUcK0pEe3V

**Why UptimeRobot instead of GitHub Actions?**
- `.github/workflows/keep-alive.yml` requires ~4,320 Actions minutes/month
- GitHub free tier: 2,000 minutes/month (would cost ~$18.56/month)
- UptimeRobot is free and purpose-built for uptime monitoring

**Deployment Steps:**
1. Push to main branch
2. Render auto-deploys from GitHub
3. Migrations run automatically via `bin/rails db:migrate`

### Environment Setup on Render

Set these in Render dashboard:
- `ANTHROPIC_API_KEY`: Your Claude API key
- `RAILS_MASTER_KEY`: From `config/master.key`
- `DATABASE_URL`: Auto-set by Render Postgres

## Common Issues

### Tailwind CSS not showing

**Problem:** Styles not rendering
**Solution:** Must run `bin/rails tailwindcss:build` or use `bin/dev`

### `current_user` undefined

**Problem:** `undefined method 'current_user'`
**Solution:** Use `Current.user` (Rails 8 convention, not `current_user`)

### API authentication failing

**Problem:** 401 Unauthorized
**Solution:** Check Bearer token format: `Authorization: Bearer <token>`

### Duplicate commit errors

**Problem:** Unique constraint violation on `commit_hash`
**Solution:** This is expected - CLI should handle gracefully (skip duplicates)

### E2E tests with CLI

**Problem:** CLI E2E tests failing
**Solution:** Ensure test server running on port 3001:

```bash
# Terminal 1
RAILS_ENV=test bin/rails db:test:prepare
RAILS_ENV=test bin/rails server -p 3001

# Terminal 2 (in commitkit-cli/)
RUN_E2E=true npm test
```

### LLM errors in tests

**Problem:** Real API calls during tests
**Solution:** Mock `LlmService` calls:

```ruby
allow(LlmService).to receive(:generate_commit_summary).and_return("summary")
```

## Project Structure

```
commitkit/
├── app/
│   ├── controllers/
│   │   ├── api/v1/              # JSON API controllers
│   │   │   ├── base_controller.rb
│   │   │   ├── commits_controller.rb
│   │   │   └── repositories_controller.rb
│   │   ├── commits_controller.rb
│   │   ├── dashboard_controller.rb
│   │   └── sessions_controller.rb
│   ├── models/
│   │   ├── user.rb
│   │   ├── repository.rb
│   │   └── commit.rb
│   ├── services/
│   │   └── llm_service.rb       # AI summary generation
│   ├── jobs/
│   │   └── generate_ai_summary_job.rb
│   └── views/                   # ERB templates
├── config/
│   ├── routes.rb
│   └── database.yml
├── db/
│   ├── migrate/                 # Database migrations
│   └── seeds.rb
├── spec/                        # RSpec tests
│   ├── factories/               # FactoryBot definitions
│   ├── models/
│   ├── requests/
│   └── services/
├── docs/                        # Design documentation
├── bin/
│   ├── dev                      # Start Puma + Tailwind
│   └── setup                    # One-command setup
└── Dockerfile                   # Production deployment
```

## Related Documentation

- **CLAUDE.md**: Full project architecture and conventions
- **docs/**: Design decisions and implementation details
- **commitkit-cli/**: Node.js CLI companion tool

## Contributing

1. Write tests first (TDD)
2. Follow Rails 8 conventions (`Current.user`, not `current_user`)
3. API controllers inherit from `Api::V1::BaseController`
4. Service objects for complex logic
5. Background jobs for async work
6. Commit frequently with descriptive messages

## Support

- GitHub Issues: [commitkit/commitkit](https://github.com/commitkit/commitkit/issues)
- Documentation: See [CLAUDE.md](../CLAUDE.md) for development guide

---

Built with Rails 8.1.1 | Powered by Anthropic Claude
