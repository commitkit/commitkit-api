# CommitKit Development Log

## November 3, 2024: Repository-Based API Refactoring

### 🎯 What We Built

Refactored CommitKit's API from a commit-centric to a repository-based architecture, making repositories first-class resources. This enables better data organization and sets the foundation for the `--delete-all-and-resync` feature.

### 📊 The Numbers

- **8 commits** in Rails API
- **1 commit** in CLI
- **24 passing** API tests
- **47 passing** CLI tests (including integration)
- **100% TDD** - Every change driven by tests first

### 🏗️ Architecture Decisions

#### Repository as First-Class Model
**Decision:** Create a Repository model instead of just storing repository_url as a string on commits.

**Why:**
- Enables proper cascade deletion (delete repository → all commits gone)
- Supports unique constraint per user (one repo URL per user)
- Cleaner RESTful API design (`POST /api/v1/repositories` instead of `/commits/batch`)
- Sets up for future features (repo-level analytics, settings, etc.)

**Trade-off:** Required updating all existing code and tests, but worth it for the architectural clarity.

#### Repository URL from Git Remote
**Decision:** Extract repository URL from `git config --get remote.origin.url` rather than asking users to provide it.

**Why:**
- Automatic - users don't need to configure anything
- Always accurate - comes directly from git
- Works for all repo types (GitHub, GitLab, Bitbucket, etc.)

**Trade-off:** Requires being in a git repository with a remote. Added clear error message for this case.

#### Required Repository Association
**Decision:** Make `repository_id` NOT NULL on commits from day one.

**Why:**
- Enforces data integrity at database level
- Every commit logically belongs to a repository
- Simpler data model (no nullable foreign keys)

**Trade-off:** Had to update all factories and existing tests, but prevented future bugs.

### 🧗 Obstacles & Solutions

#### 1. **Test File Confusion**
**Problem:** Had both `commits_controller_spec.rb` and `commits_spec.rb` - unclear which was which.

**Root Cause:** `commits_controller_spec.rb` had old batch endpoint tests that should have been moved when we created repositories.

**Solution:** Deleted `commits_controller_spec.rb`, consolidated all tests into properly named files (`commits_spec.rb` for commits, `repositories_spec.rb` for repositories).

**Lesson:** Keep test files organized by resource, not by when they were created.

#### 2. **Single Responsibility Principle Violation**
**Problem:** Initially tried to handle both individual and bulk deletes in one controller action.

**User Feedback:** "This should be a different controller action (single responsibility principle)."

**Solution:**
- Individual commit delete: `DELETE /api/v1/commits/:id` in CommitsController
- Bulk delete via repository: `DELETE /api/v1/repositories/:id` in RepositoriesController

**Lesson:** Even when functionality seems similar, separate concerns lead to cleaner code.

#### 3. **TDD Discipline**
**Problem:** Early on, tried to implement multiple features at once before seeing tests fail.

**User Feedback:** "Can we do this TDD style for real, i.e. we add the simplest code to get to the next test failure?"

**Solution:** Strict Red-Green-Refactor cycle:
1. Write ONE test
2. Run it (see RED)
3. Write MINIMAL code to pass
4. Run it (see GREEN)
5. Refactor if needed
6. Repeat

**Example:**
```ruby
# Test 1: Create repository and commits - RED
it "creates repository and multiple commits" do
  expect { post ... }.to change(Repository, :count).by(1)
end

# Minimal implementation - GREEN
def create
  repository = current_user.repositories.create!(url: params[:url])
  # ... hardcoded response
end

# Test 2: Find existing repository - RED
it "finds existing repository instead of creating duplicate" do
  expect { post ... }.to change(Repository, :count).by(0)
end

# Update to use find_or_create_by! - GREEN
def create
  repository = current_user.repositories.find_or_create_by!(url: params[:url])
  # ...
end
```

**Lesson:** TDD works best with baby steps. Each test should drive exactly one small change.

### 🔄 API Changes

#### Before
```ruby
# Individual commit
POST /api/v1/commits
{ commit: { commit_hash, message, summary } }

# Batch
POST /api/v1/commits/batch
{ commits: [...] }
```

#### After
```ruby
# Individual commit (auto-detects repository)
POST /api/v1/commits
{ commit: { commit_hash, message, summary, repository_url } }

# Batch (repository-centric)
POST /api/v1/repositories
{ url: "https://github.com/user/repo", commits: [...] }

# Delete repository and all commits
DELETE /api/v1/repositories/:id

# Delete individual commit
DELETE /api/v1/commits/:id
```

### 🧪 Testing Strategy

#### Rails API
- **Model tests:** Associations, validations, uniqueness constraints
- **Request specs:** Full HTTP request/response cycle for all endpoints
- **TDD cycle:** Red → Green for every feature

#### CLI
- **Unit tests:** Individual functions (getRepositoryUrl, sendCommit, batchCommits)
- **Integration tests:** End-to-end sync with mocked API
- **E2E tests:** Real git repo → real API (skipped by default, run with RUN_E2E=true)

### 💡 Key Learnings

1. **Start with the simplest test** - Don't write complex tests first
2. **One test, one change** - Each test should drive exactly one small implementation
3. **Resource-based APIs are cleaner** - `/repositories` with commits nested is more RESTful than `/commits/batch`
4. **Database constraints + model validations** - Belt and suspenders for data integrity
5. **Test organization matters** - Clear file naming prevents confusion later

### 🎬 What's Next

With this foundation in place, we can now implement:
- `commitkit sync --delete-all-and-resync` flag
- Repository filter in the UI
- Settings page for API token and quick setup

### 📝 Quote of the Session

> "Can we do this TDD style for real, i.e. we add the simplest code to get to the next test failure?"

A good reminder that TDD isn't about writing tests - it's about letting tests drive the simplest possible implementation.

---

**Tech Stack:** Rails 8.1, RSpec, FactoryBot, Shoulda-matchers, Node.js, Jest
**Methodology:** Test-Driven Development (TDD)
**Pair Programming Partner:** Claude (Anthropic)
