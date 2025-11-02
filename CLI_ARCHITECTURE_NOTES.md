# CommitKit CLI Architecture & Implementation Plan
## Session Date: 2025-11-02

---

## Overview

This document captures the architectural decisions and implementation plan for the CommitKit CLI tool, including git hook improvements, background worker implementation, LLM integration, and comprehensive commit filtering.

---

## Core Architecture Decisions

### 1. Git as Source of Truth

**Decision:** Git repository history is the authoritative source for commit tracking.

**Implications:**
- No "work-history" mode - commits deleted from git are deleted from API
- No relationship tracking (amended_from, squashed_into, etc.)
- Simpler sync logic: compare git history to API, delete what's missing
- User's git manipulations (reset, rebase, amend) are respected

**Sync Implementation:**
```javascript
async function sync() {
  const gitCommits = execSync('git log --all --format=%H').split('\n');
  const apiCommits = await api.getCommits(repoId);

  // Delete from API if not in git
  for (const apiCommit of apiCommits) {
    if (!gitCommits.includes(apiCommit.hash)) {
      await api.deleteCommit(apiCommit.hash);
    }
  }
}
```

**Rationale:**
- Matches user expectations (git is their mental model)
- Eliminates complex edge case handling
- Respects privacy (force-push removes sensitive data everywhere)
- Simpler to implement and maintain

---

### 2. Background Worker Architecture

**Decision:** Non-blocking background worker with job queue for LLM analysis and API calls.

**Why Necessary:**
- LLM analysis can take 5-30 seconds
- Cannot block terminal after git commit
- Multiple commits in rapid succession must be handled
- Offline commits must be queued for later sync

**Implementation:**

**Git Hook (Fast Path - Always <100ms):**
```javascript
async function postCommitHook() {
  // 1. Check if commit should be tracked (skip rules)
  const decision = await shouldTrackCommit();
  if (!decision.track) {
    console.log(`⏭️  CommitKit: ${decision.reason}`);
    process.exit(0);
  }

  // 2. Queue commit for processing (atomic append)
  appendToQueue({
    type: 'track-commit',
    commit: extractCommitData(),
    timestamp: Date.now()
  });

  // 3. Wake up worker (non-blocking)
  wakeupWorker();

  // Hook exits immediately - terminal unblocked
}
```

**Background Worker:**
```javascript
// commitkit worker
function runWorker() {
  // Acquire lock (prevents concurrent workers)
  if (!acquireLock()) {
    process.exit(0); // Another worker running
  }

  try {
    while (true) {
      const jobs = readQueue();
      if (jobs.length === 0) break;

      for (const job of jobs) {
        try {
          await processJob(job); // LLM + API call
          removeFromQueue(job);
        } catch (error) {
          handleJobError(job, error); // Retry logic
        }
      }
    }
  } finally {
    releaseLock();
  }

  // Worker exits when queue empty (no persistent daemon)
}
```

**Key Features:**
- Lock file prevents concurrent workers
- Stale lock detection (check if PID still exists)
- Retry logic with exponential backoff
- Dead letter queue for permanently failed jobs
- Worker only runs when work exists (no persistent daemon)

**Error Handling:**
```javascript
// Stale lock detection
function acquireLock() {
  const lockfile = '~/.commitkit/worker.lock';

  if (fs.existsSync(lockfile)) {
    const pid = parseInt(fs.readFileSync(lockfile, 'utf8'));

    try {
      process.kill(pid, 0); // Check if process exists
      return false; // Lock valid, another worker running
    } catch (e) {
      // Process dead, remove stale lock
      fs.unlinkSync(lockfile);
    }
  }

  fs.writeFileSync(lockfile, process.pid.toString());
  return true;
}

// Retry with backoff
async function processJob(job) {
  try {
    await trackCommitWithLLM(job);
  } catch (error) {
    job.retries = (job.retries || 0) + 1;

    if (job.retries > 3) {
      moveToDeadLetter(job);
    } else {
      // Keep in queue for retry
      job.nextRetry = Date.now() + (Math.pow(2, job.retries) * 1000);
    }

    throw error;
  }
}
```

---

### 3. LLM Integration Strategy (Hybrid: BYOK + MCP)

**Decision:** Support two LLM integration methods - BYOK (automatic) as primary, MCP (on-demand) as alternative.

#### Option A: BYOK - Bring Your Own Key (Primary, Automatic)

**How It Works:**
```bash
# User configures their API key
commitkit config-llm --provider anthropic --api-key sk-ant-...

# From then on, every commit is automatically analyzed
git commit -m "Add authentication"
# → Hook captures commit
# → Background worker calls Anthropic API using user's key
# → Summary generated and saved
# → User opens dashboard, summary is already there
```

**Benefits:**
✅ Fully automatic - no manual trigger needed
✅ User pays Anthropic/OpenAI directly (via their own API key)
✅ Works without IDE integration
✅ CommitKit has $0 LLM API costs (we don't handle payments)
✅ Consistent analysis quality (Claude 3.5 Sonnet, GPT-4)

**Cost to User (paid to Anthropic/OpenAI, not CommitKit):**
- Claude 3.5 Sonnet: ~$0.0015 per commit
- GPT-4 Turbo: ~$0.005 per commit
- Example: 1000 commits/month ≈ $1.50-$5/month on their LLM provider bill

**User Experience:**
- Configure once: `commitkit config-llm --provider anthropic --api-key sk-ant-...`
- Make commits normally
- Summaries appear automatically in dashboard
- No IDE integration needed

**Providers Supported:**
1. Anthropic (Claude 3.5 Sonnet, Claude 3 Opus)
2. OpenAI (GPT-4, GPT-4 Turbo)
3. Google (Gemini Pro) - future

#### Option B: MCP - Model Context Protocol (Alternative, On-Demand)

**Key Insight:** All major AI coding assistants now support MCP (Model Context Protocol) as of 2025.

**Architecture:**
```
User makes commit
  ↓
Git hook tracks commit (no LLM yet)
  ↓
User in IDE asks: "Summarize my recent work"
  ↓
IDE LLM calls MCP server: get_commit_context
  ↓
MCP returns commit data
  ↓
IDE LLM analyzes and responds
  ↓
User can save analysis back via MCP: save_analysis
```

**CommitKit MCP Server:**
```javascript
// mcp/server.js
import { Server } from '@modelcontextprotocol/sdk/server/index.js';

const server = new Server({
  name: 'commitkit',
  version: '1.0.0',
});

// Tool 1: Get commit context
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: 'get_commit_context',
      description: 'Get commit data with repo context for analysis',
      inputSchema: {
        type: 'object',
        properties: {
          commit_hash: { type: 'string' },
          include_diff: { type: 'boolean' },
          include_repo_summary: { type: 'boolean' }
        }
      }
    },
    {
      name: 'save_analysis',
      description: 'Save LLM analysis back to CommitKit',
      inputSchema: {
        type: 'object',
        properties: {
          commit_hash: { type: 'string' },
          summary: { type: 'string' },
          tags: { type: 'array' }
        }
      }
    }
  ]
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  if (request.params.name === 'get_commit_context') {
    return {
      commit: getCommitData(request.params.arguments.commit_hash),
      repo_summary: getRepoSummary(),
      related_files: getRelatedFiles()
    };
  }

  if (request.params.name === 'save_analysis') {
    await saveToAPI(request.params.arguments);
    return { success: true };
  }
});
```

**Package.json:**
```json
{
  "name": "commitkit",
  "bin": {
    "commitkit": "cli/index.js"
  },
  "main": "mcp/server.js",
  "exports": {
    ".": "./cli/index.js",
    "./mcp": "./mcp/server.js"
  }
}
```

**IDE Configuration (Automatic):**
```bash
# During commitkit init
commitkit setup-mcp

# Shows:
Add to your IDE's MCP config:

Claude Code (~/.config/claude-code/mcp.json):
{
  "mcpServers": {
    "commitkit": {
      "command": "node",
      "args": ["/usr/local/lib/node_modules/commitkit/mcp/server.js"]
    }
  }
}

# Or: commitkit setup-mcp --auto
# (Attempts automatic registration with permission)
```

**Benefits:**
- Works with Claude Code, Copilot, Cursor, Windsurf automatically
- One implementation supports 4+ IDEs
- Standard protocol maintained by Anthropic
- User pays for their own LLM (via IDE subscription)
- No API costs for CommitKit

#### Option B: Direct LLM Detection (MVP/Fallback)

**For MVP, simpler approach:**
```javascript
async function detectAndAnalyze(commitData) {
  // Try local LLMs in order
  if (await detectOllama()) {
    return await analyzeWithOllama(commitData);
  }

  if (await detectLMStudio()) {
    return await analyzeWithLMStudio(commitData);
  }

  // No LLM available - send commit without analysis
  return null;
}
```

**Detection:**
```javascript
async function detectOllama() {
  try {
    const response = await fetch('http://localhost:11434/api/tags');
    return response.ok;
  } catch {
    return false;
  }
}
```

---

### 4. Comprehensive Commit Filtering System

**Decision:** Three-layered skip/track system with opt-in and opt-out modes.

#### Skip Methods (Priority Order)

**1. Environment Variables (Highest Priority)**
```bash
# Skip individual commit
COMMITKIT_SKIP=1 git commit -m "Private experiment"

# Track individual commit (in opt-in mode)
COMMITKIT_TRACK=1 git commit -m "Important feature"
```

**2. Git Notes**
```bash
git commit -m "Some work"
git notes add -m "commitkit:skip"

# Or force track
git notes add -m "commitkit:track"
```

**3. `.commitkit-ignore` File (Most Comprehensive)**
```yaml
# === Commit Message Patterns ===
message_patterns:
  - "WIP:*"
  - "[private]*"
  - "*experiment*"
  - "fixup!*"
  - "squash!*"
  - "temp:*"

# === File Patterns ===
file_patterns:
  - "*.log"
  - "*.tmp"
  - "**/.env*"
  - "**/secrets/*"
  - "package-lock.json"
  - "yarn.lock"

# === Author Patterns ===
authors:
  - "bot@"
  - "dependabot"
  - "renovate"

# === Branch Patterns ===
branches:
  - "tmp/*"
  - "experiment/*"
  - "spike/*"

# === Time-based Rules ===
time_rules:
  skip_hours: [0, 1, 2, 3, 4, 5]  # Skip late-night commits

# === Commit Size Rules ===
size_rules:
  skip_if_lines_changed_less_than: 2
  skip_if_files_changed_more_than: 50

# === Custom Rules ===
custom:
  skip_merge_commits: true
  skip_revert_commits: true
  skip_if_no_code_changes: true  # Docs/config only

# === Diff Content Patterns ===
diff_patterns:
  - "*console.log*"
  - "*debugger*"
  - "*TODO:*"

# === Directory Patterns ===
directory_patterns:
  - "tests/**"      # Test-only commits
  - "docs/**"       # Docs-only commits
  - ".github/**"    # CI config only
```

#### Mode Selection

**During `commitkit init`:**
```bash
⚙️  Tracking Configuration

How should CommitKit track commits in this repository?

1. Track all commits (default)
   • All commits are tracked automatically
   • Use COMMITKIT_SKIP=1 or .commitkit-ignore to exclude specific commits
   • Best for: Personal projects, solo work

2. Track only explicitly marked commits
   • Only commits with COMMITKIT_TRACK=1 are tracked
   • Use for sensitive repositories or shared repos
   • Best for: Work projects, client code

Choose [1/2]: 1
```

**Stored in `.commitkit/config` (repo-level):**
```json
{
  "mode": "opt-out",  // or "opt-in"
  "ignoreFile": ".commitkit-ignore",
  "created": "2024-01-15T10:30:00Z"
}
```

#### Decision Logic

```javascript
async function shouldTrackCommit() {
  const config = readRepoConfig();
  const commit = getCommitData();

  // 1. Check environment variable (highest priority)
  if (process.env.COMMITKIT_SKIP === '1') {
    return { track: false, reason: 'ENV: COMMITKIT_SKIP=1' };
  }

  if (process.env.COMMITKIT_TRACK === '1') {
    return { track: true, reason: 'ENV: COMMITKIT_TRACK=1' };
  }

  // 2. Check git notes
  const notes = getGitNotes(commit.hash);
  if (notes.includes('commitkit:skip')) {
    return { track: false, reason: 'Git notes: commitkit:skip' };
  }
  if (notes.includes('commitkit:track')) {
    return { track: true, reason: 'Git notes: commitkit:track' };
  }

  // 3. Check .commitkit-ignore file
  const ignoreRules = readIgnoreFile();
  const ignoreMatch = checkIgnoreRules(commit, ignoreRules);
  if (ignoreMatch) {
    return { track: false, reason: `Ignore rule: ${ignoreMatch}` };
  }

  // 4. Apply mode (opt-in vs opt-out)
  if (config.mode === 'opt-in') {
    return { track: false, reason: 'Opt-in mode: no explicit track flag' };
  } else {
    return { track: true, reason: 'Opt-out mode: default behavior' };
  }
}
```

#### Helper Commands

```bash
# Show why a commit was/wasn't tracked
commitkit explain <commit-hash>

# Test ignore rules
commitkit test-ignore
# Prompts for: message, files, author, branch
# Shows: Would be TRACKED or SKIPPED and why

# Generate default ignore file
commitkit init-ignore

# Add pattern interactively
commitkit ignore add
```

---

### 5. Git Hook Chaining (Already Implemented)

**Current Implementation:** Bash shell script that runs user's existing hook first, then CommitKit tracking.

**Hook Structure:**
```bash
#!/bin/bash

# CommitKit post-commit hook

# Execute original user hook first (if exists)
ORIGINAL_HOOK="/path/to/.git/hooks/post-commit.pre-commitkit"
if [ -f "$ORIGINAL_HOOK" ]; then
  "$ORIGINAL_HOOK" "$@"
  HOOK_EXIT_CODE=$?
  if [ $HOOK_EXIT_CODE -ne 0 ]; then
    echo "Original hook failed, skipping CommitKit tracking"
    exit $HOOK_EXIT_CODE
  fi
fi

# Run CommitKit tracking (Node.js via heredoc)
node <<'COMMITKIT_EOF'
try {
  // All CommitKit logic here
  const commitData = extractCommitData();
  queueForProcessing(commitData);
} catch (error) {
  // Log error, don't block commit
  logError(error);
  process.exit(0);
}
COMMITKIT_EOF
```

**Benefits:**
- User's hooks run first
- CommitKit respects hook failures
- Both hooks execute successfully
- No user workflow disruption

**Installation:**
- If existing hook: Save as `.post-commit.pre-commitkit`, create combined hook
- If no existing hook: Install CommitKit hook directly
- Uninstall: Restore original hook automatically

---

## MVP Scope (Consensus from Design Review)

### CRITICAL (Must Have for MVP)

1. **Background worker with queue**
   - Non-blocking git hook
   - Job queue for commits
   - Lock file coordination
   - Retry logic

2. **commitkit sync command**
   - Upload existing commit history on first setup
   - Walk git log --all to get all commits
   - Send to API in batches
   - Show progress indicator
   - Support --dry-run flag
   - Essential for initial setup

3. **BYOK LLM Integration (Primary)**
   - User provides their own API key (Anthropic, OpenAI, etc.)
   - Background worker automatically analyzes every commit
   - **User pays Anthropic/OpenAI directly:** ~$0.0015 per commit (Claude 3.5 Sonnet)
   - **CommitKit pays:** $0 (we never touch LLM API costs)
   - Fully automatic, no manual trigger needed
   - Example: 1000 commits/month ≈ $1.50 charged to user's Anthropic account

4. **commitkit config-llm command**
   - Configure LLM provider and API key
   - Support Anthropic (Claude) and OpenAI (GPT-4)
   - Secure storage (~/.commitkit/llm-config.json, mode 0600)
   - Test API key validation

5. **MCP Server Implementation (Alternative)**
   - Build Model Context Protocol server for IDE integration
   - Supports Claude Code, Copilot, Cursor, Windsurf
   - Exposes get_commit_context and save_analysis tools
   - User-initiated analysis (not automatic)
   - Uses existing IDE AI subscription (no API key needed)
   - One implementation works across all IDEs

6. **commitkit setup-mcp command**
   - Show IDE-specific setup instructions
   - Optional --auto flag for automatic configuration
   - Backs up existing configs before modification

7. **Git as source of truth**
   - Simple sync: delete commits not in git
   - No relationship tracking
   - Respect git history

8. **Comprehensive skip system**
   - Environment variables
   - Git notes
   - `.commitkit-ignore` file
   - Opt-in/opt-out modes

9. **Integration tests**
   - Real git repo
   - Real commit
   - Verify hook ran
   - Verify API called
   - Test BYOK LLM analysis
   - Test MCP server tools

10. **Cross-platform CI**
    - Test on Windows, Mac, Linux
    - Test Node 18.x and 20.x

### HIGH PRIORITY (Should Have)

11. Error handling with try-catch
12. Error logging to `~/.commitkit/errors.log`
13. `commitkit logs` command
14. Git command optimization (5 calls → 1 call)
15. Enhanced communication/transparency in `commitkit init`

### POST-MVP (V0.2+)

- Local LLM detection (Ollama, LM Studio) as fallback option
- Hybrid LLM analysis (try MCP, fallback to local LLM)
- `commitkit doctor` command
- `commitkit purge` command
- Advanced sync features (--from-date, --branch, etc.)
- Repo summarization

---

## Implementation Improvements from Code Review

### 1. Single Git Command Optimization

**Before (5 separate process spawns):**
```javascript
const commitHash = execSync('git rev-parse HEAD').trim();
const commitMessage = execSync('git log -1 --pretty=%B').trim();
const authorName = execSync('git log -1 --pretty=%an').trim();
const authorEmail = execSync('git log -1 --pretty=%ae').trim();
const committedAt = execSync('git log -1 --pretty=%cI').trim();
```

**After (1 process spawn):**
```javascript
const info = execSync(
  'git log -1 --pretty=format:%H%x1F%B%x1F%an%x1F%ae%x1F%cI',
  { encoding: 'utf8' }
).trim();

// Split on ASCII unit separator (handles newlines in commit messages)
const [commitHash, commitMessage, authorName, authorEmail, committedAt] =
  info.split('\x1F');
```

**Benefits:**
- 5x fewer process spawns
- Faster on Windows (process creation is expensive)
- Handles multi-line commit messages correctly

### 2. Comprehensive Error Handling

**All hook code wrapped in try-catch:**
```javascript
node <<'COMMITKIT_EOF'
try {
  // All hook logic
  const commitData = extractCommitData();
  queueCommit(commitData);
  wakeupWorker();
} catch (error) {
  // Log error for debugging
  const fs = require('fs');
  const path = require('path');
  const os = require('os');

  const errorLog = path.join(os.homedir(), '.commitkit', 'errors.log');
  const timestamp = new Date().toISOString();
  const errorEntry = `[${timestamp}] ${error.message}\n${error.stack}\n\n`;

  try {
    fs.appendFileSync(errorLog, errorEntry);
  } catch (logError) {
    // Can't even log - fail silently
  }

  process.exit(0); // Don't block commit
}
COMMITKIT_EOF
```

**Benefits:**
- Never blocks commits (even on catastrophic errors)
- Errors logged for later debugging
- User can run `commitkit logs` to see issues
- Silent failure better than broken commits

### 3. Edge Case Tests

**Test coverage for:**
- Multiline commit messages
- Emoji in messages (🎉 Add feature 🚀)
- Special characters ("quotes" & <brackets> $variables)
- Very long messages (10,000+ characters)
- Non-ASCII characters (Chinese, Russian, etc.)
- Empty messages
- Binary file commits
- Large commits (50+ files)

```javascript
describe('Commit Message Edge Cases', () => {
  it('handles multiline messages', async () => {
    const message = 'Title\n\nBody paragraph 1\n\nBody paragraph 2';
    const commit = await createTestCommit(message);
    expect(commit.message).toBe(message);
  });

  it('handles emoji in messages', async () => {
    const message = '🎉 Add new feature 🚀';
    const commit = await createTestCommit(message);
    expect(commit.message).toBe(message);
  });

  // ... more edge cases
});
```

---

## API Schema Changes

### Commits Table Updates

**No changes needed!** Current schema already supports summary field:

```ruby
create_table :commits do |t|
  t.references :user, null: false, foreign_key: true
  t.string :commit_hash, null: false
  t.text :message
  t.text :summary  # ← Already exists for LLM analysis
  t.timestamps
end
```

### Future Enhancements (Post-MVP)

**If we add tags:**
```ruby
# Add tags column
add_column :commits, :tags, :string, array: true, default: []
add_index :commits, :tags, using: :gin

# Or separate table for many-to-many
create_table :tags do |t|
  t.string :name, null: false, index: { unique: true }
  t.timestamps
end

create_table :commit_tags do |t|
  t.references :commit, null: false, foreign_key: true
  t.references :tag, null: false, foreign_key: true
  t.index [:commit_id, :tag_id], unique: true
end
```

**If we add LLM metadata:**
```ruby
add_column :commits, :llm_analysis, :jsonb, default: {}
add_index :commits, :llm_analysis, using: :gin

# Stores:
# {
#   "provider": "ollama",
#   "model": "llama2",
#   "complexity": "medium",
#   "impact": "Prevents session timeout errors",
#   "analyzed_at": "2024-01-15T10:30:00Z"
# }
```

---

## Testing Strategy

### Unit Tests (Jest)

**Already Have (23 tests):**
- Config module (5 tests)
- API module (6 tests)
- Git hook module (12 tests)

**Need to Add:**
- Background worker tests
- Queue management tests
- LLM detection tests
- Skip/track decision logic tests
- Edge case message parsing tests

### Integration Tests (New)

**Test Structure:**
```javascript
// __tests__/integration/
describe('Full Commit Flow', () => {
  let testRepo;
  let mockApiServer;

  beforeEach(async () => {
    testRepo = await createTempGitRepo();
    mockApiServer = await startMockAPI();
  });

  afterEach(async () => {
    await cleanupRepo(testRepo);
    await mockApiServer.close();
  });

  it('tracks real commit end-to-end', async () => {
    // 1. Configure commitkit
    await runCommand(`commitkit config ${testApiToken}`);

    // 2. Initialize in test repo
    await runCommand(`commitkit init`, { cwd: testRepo });

    // 3. Make a real git commit
    writeFile(testRepo, 'test.txt', 'content');
    await runCommand(`git add .`, { cwd: testRepo });
    await runCommand(`git commit -m "Test commit"`, { cwd: testRepo });

    // 4. Wait for background worker
    await waitForWorkerCompletion();

    // 5. Verify API received commit
    const commits = await mockApiServer.getReceivedCommits();
    expect(commits).toHaveLength(1);
    expect(commits[0].message).toBe('Test commit');
  });

  it('chains with existing hooks', async () => {
    // Create existing hook
    writeHook(testRepo, 'post-commit', '#!/bin/bash\necho "original"');

    // Install commitkit
    await runCommand(`commitkit init`, { cwd: testRepo });

    // Commit
    await makeCommit(testRepo, 'Test');

    // Verify both hooks ran
    const output = await getCommitOutput(testRepo);
    expect(output).toContain('original');
    expect(output).toContain('CommitKit');
  });
});
```

### Cross-Platform CI

**GitHub Actions Matrix:**
```yaml
strategy:
  matrix:
    os: [ubuntu-latest, macos-latest, windows-latest]
    node: [18.x, 20.x]

steps:
  - uses: actions/checkout@v4
  - uses: actions/setup-node@v4
    with:
      node-version: ${{ matrix.node }}
  - run: npm ci
  - run: npm test
  - run: npm run test:integration
```

**Tests 6 combinations:**
- Ubuntu + Node 18
- Ubuntu + Node 20
- macOS + Node 18
- macOS + Node 20
- Windows + Node 18
- Windows + Node 20

---

## File Structure

```
commitkit-cli/
├── package.json
├── index.js                    # Main CLI entry point
├── cli/
│   ├── commands/
│   │   ├── config.js          # commitkit config
│   │   ├── init.js            # commitkit init
│   │   ├── status.js          # commitkit status
│   │   ├── sync.js            # commitkit sync
│   │   ├── logs.js            # commitkit logs
│   │   ├── explain.js         # commitkit explain
│   │   └── worker.js          # commitkit worker (background)
│   └── utils/
│       ├── git.js             # Git operations
│       ├── queue.js           # Job queue management
│       └── lock.js            # Lock file handling
├── lib/
│   ├── config.js              # Config management
│   ├── api.js                 # API client
│   ├── git-hook.js            # Hook installation
│   ├── llm.js                 # LLM detection & analysis
│   └── ignore.js              # .commitkit-ignore parsing
├── mcp/
│   └── server.js              # MCP server (post-MVP)
├── __tests__/
│   ├── unit/
│   │   ├── config.test.js
│   │   ├── api.test.js
│   │   ├── git-hook.test.js
│   │   ├── worker.test.js
│   │   └── ignore.test.js
│   └── integration/
│       ├── full-flow.test.js
│       └── hook-chaining.test.js
└── .github/
    └── workflows/
        ├── ci.yml             # Test on push
        └── cross-platform.yml # Matrix testing
```

---

## CLI Commands Reference

### Core Commands (MVP)

```bash
# Setup
commitkit config <api-token>              # Configure API token
commitkit config <api-token> --url <url>  # With custom API URL
commitkit init                             # Install git hooks
commitkit init --mode=opt-in               # Opt-in tracking mode

# Status
commitkit status        # Show config and tracking status
commitkit logs          # Show error log
commitkit logs --clear  # Clear error log

# Filtering
commitkit explain <hash>      # Show why commit was/wasn't tracked
commitkit test-ignore         # Test ignore rules interactively
commitkit init-ignore         # Generate default .commitkit-ignore
commitkit ignore add          # Add ignore pattern interactively

# Sync
commitkit sync                # Sync git history with API
commitkit sync --dry-run      # Show what would change

# Maintenance
commitkit uninstall           # Remove hooks
commitkit worker              # Run background worker (internal)
commitkit worker-status       # Check if worker is running
```

### Advanced Commands (Post-MVP)

```bash
commitkit doctor              # System diagnostics
commitkit purge <hash>        # Remove commit from API permanently
commitkit setup-mcp           # Setup MCP server integration
commitkit setup-mcp --auto    # Auto-register with IDEs
```

---

## Development Timeline

### Week 1: Core Infrastructure
- ✅ Git hook with chaining (already done)
- Background worker implementation
- Job queue system
- Lock file management
- Error handling & logging

### Week 2: Filtering & LLM
- Skip/track decision logic
- `.commitkit-ignore` parsing
- Environment variable support
- Git notes support
- LLM detection (Ollama, LM Studio)
- Basic LLM analysis

### Week 3: Testing
- Unit test expansion
- Integration test suite
- Cross-platform CI setup
- Edge case testing
- Manual QA

### Week 4: Polish & Release
- Documentation
- CLI help text
- Error messages
- Beta testing
- npm publish

---

## Open Questions & Decisions Needed

### 1. Queue Format

**Option A: JSONL (One job per line)**
```
{"type":"track-commit","commit":{...},"timestamp":1234567890}
{"type":"track-commit","commit":{...},"timestamp":1234567891}
```
- Pros: Atomic append, easy to parse line-by-line
- Cons: Manual parsing, no built-in validation

**Option B: JSON Array**
```json
[
  {"type":"track-commit","commit":{...}},
  {"type":"track-commit","commit":{...}}
]
```
- Pros: Standard JSON, easy validation
- Cons: Not atomic (must read-modify-write with lock)

**Recommendation:** JSONL for atomicity

### 2. Error Log Rotation

**Current:** Append-only, grows forever

**Options:**
- Keep last 100 errors
- Keep last 7 days
- Keep last 1MB
- Let user clear manually

**Recommendation:** Keep last 100 errors OR 7 days, whichever is more recent

### 3. Default Mode

**Options:**
- Opt-out (track all, user skips specific commits)
- Opt-in (track none, user marks commits to track)

**Recommendation:** Opt-out for MVP (matches user expectations, less friction)

### 4. LLM Analysis Timing

**Options:**
A. Inline (during worker processing)
B. Deferred (track first, analyze later on-demand)
C. Hybrid (try inline, fall back to deferred)

**Recommendation:** C - Hybrid approach
- Try LLM analysis during background worker
- If LLM unavailable or slow, send commit without analysis
- User can trigger analysis later: `commitkit analyze --all`

---

## Alternatives Considered and Rejected

This section documents the architectural alternatives we discussed during the design review and explains why we chose not to pursue them.

---

### Alternative 1: Work-History Mode (Track All Commits Forever)

**What it was:**
A mode where CommitKit tracks every commit ever made, regardless of whether it still exists in git history. When a commit is rebased, amended, or reset, we would maintain relationship tracking (e.g., `amended_from`, `squashed_into`, `reset_from`) to preserve the full work history.

**Why it seemed appealing:**
- Complete record of all work, even deleted/rewritten commits
- Could show "true" time spent on features
- Useful for detailed time tracking and productivity analysis
- Resume bullet points could reference work that was later refactored

**Why we rejected it:**

1. **Complex Sync Logic**: Requires sophisticated relationship tracking
   ```javascript
   // Would need complex logic like:
   if (commitExists(hash) && apiHas(hash)) {
     // Commit still exists
   } else if (!commitExists(hash) && apiHas(hash)) {
     // Was it amended? Rebased? Reset? Squashed?
     // Need to detect which and create relationship
     detectRelationship(hash);
   }
   ```

2. **Privacy Concerns**: Users might force-push to remove sensitive data (credentials, PII). Work-history mode would keep this data in our API, violating user intent.

3. **Database Bloat**: Developers regularly rebase, amend, and squash commits. Over time, the API would contain 3-5x more commits than actually exist in git.

4. **Doesn't Match User Mental Model**: When a developer runs `git reset --hard HEAD~5`, their mental model is "I deleted those commits." Having them still appear in CommitKit would be confusing and frustrating.

5. **Implementation Complexity**: Would need:
   - Relationship detection algorithms
   - Multiple commit states (active, amended, squashed, deleted)
   - Complex UI to show relationships
   - Migration path for existing data

**Final Decision:** Git is source of truth. Commits deleted from git are deleted from API. Simple, predictable, respects user intent.

---

### Alternative 2: Persistent Daemon Process

**What it was:**
Instead of a short-lived background worker, run a persistent daemon process (`commitkitd`) that stays running in the background 24/7, listening for commits to process.

**Why it seemed appealing:**
- No startup overhead for each commit
- Could maintain connection pool to API
- Could batch multiple rapid commits efficiently
- Daemon can monitor git directly (no hook needed)

**Why we rejected it:**

1. **Resource Usage**: Daemon consumes memory and CPU even when not processing commits. On a developer's machine with dozens of repos, this adds up.

2. **Complexity**:
   - How does daemon start? (launchd on Mac, systemd on Linux, Task Scheduler on Windows)
   - How does daemon restart after crashes?
   - How does daemon update when CLI is updated?
   - How does user stop/start daemon?

3. **Permission Issues**: Daemon typically runs as separate user, creating permission issues accessing git repos in user directories.

4. **Debugging Difficulty**: When something breaks, users can't easily see why. With short-lived worker, logs are simple and errors are immediate.

5. **Multi-Repo Coordination**: One daemon for all repos means complex state management and potential conflicts.

**Final Decision:** Short-lived background worker that runs only when there are jobs in the queue, then exits. Simple, predictable, no resource waste.

---

### Alternative 3: Automatic IDE Configuration Modification

**What it was:**
During `commitkit init`, automatically modify the user's IDE configuration files (VS Code settings.json, Claude Code mcp.json, etc.) to register the MCP server without user intervention.

**Why it seemed appealing:**
- One-command setup: `commitkit init` does everything
- No manual JSON editing required
- Better user experience (less friction)

**Why we rejected it:**

1. **Permission Issues**: Modifying user config files without explicit permission feels invasive and could be seen as malware-like behavior.

2. **Breakage Risk**: What if:
   - Config file has custom formatting (comments, trailing commas)?
   - Config file is symlinked to dotfiles repo?
   - Config file has syntax error (our modification makes it worse)?
   - IDE has config file open with unsaved changes?

3. **IDE Diversity**: Each IDE stores MCP config differently:
   - Claude Code: `~/.config/claude-code/mcp.json`
   - Cursor: `~/.cursor/extensions.json`
   - VS Code: `~/.config/Code/User/settings.json` under `mcp.servers`
   - Windsurf: Unknown location (could change)

4. **Version Conflicts**: What if user already has a different version of CommitKit MCP server registered? Do we overwrite? Merge? Error?

5. **Uninstall Complexity**: `commitkit uninstall` would need to reverse these changes perfectly.

**Final Decision:** Show clear instructions and offer `commitkit setup-mcp --auto` for users who explicitly want automatic modification. Default to manual setup with copy-paste instructions.

---

### Alternative 4: Relationship Tracking (amended_from, squashed_into, etc.)

**What it was:**
When a commit is amended or squashed, instead of deleting the old commit, mark it as superseded and create a relationship:

```javascript
// Old commit
{
  hash: "abc123",
  status: "amended",
  amended_to: "def456"
}

// New commit
{
  hash: "def456",
  amended_from: "abc123"
}
```

**Why it seemed appealing:**
- Preserves work history
- Shows evolution of work
- Useful for "before/after" analysis
- Could track squashed commits back to original work

**Why we rejected it:**

1. **Detection is Hard**: How do we know `def456` is an amended version of `abc123`?
   - Same author? (not always)
   - Similar message? (could be coincidence)
   - Similar diff? (requires expensive computation)
   - Same timestamp range? (unreliable)

2. **False Positives**: Risk of incorrectly linking unrelated commits:
   ```
   git commit -m "Fix bug"        # abc123
   git reset --hard HEAD~1
   git commit -m "Fix bug"        # def456 (unrelated fix)
   # System incorrectly thinks def456 amended abc123
   ```

3. **Rebase Complexity**: After interactive rebase with reorder + squash + edit, the relationships become impossibly complex.

4. **User Value Unclear**: What would users actually do with this information? The complexity outweighs the benefit.

5. **Implementation Burden**: Requires:
   - Heuristic detection algorithms
   - Confidence scores
   - UI to display relationships
   - Database schema changes
   - Migration complexity

**Final Decision:** Simple active/deleted status. No relationship tracking. If commit exists in git, it's active. If not, delete it from API.

---

### Alternative 5: Individual IDE Integrations

**What it was:**
Instead of building an MCP server, build direct integrations for each IDE:
- VS Code extension
- Cursor integration
- Claude Code integration
- Windsurf integration

**Why it seemed appealing:**
- More control over UX
- Could add IDE-specific features (status bar, notifications)
- No dependency on MCP protocol
- Richer integration possibilities

**Why we rejected it:**

1. **Maintenance Burden**: 4+ separate codebases to maintain:
   ```
   commitkit-vscode/       # TypeScript, VS Code API
   commitkit-cursor/       # Different API
   commitkit-claude/       # Different API again
   commitkit-windsurf/     # Yet another API
   ```

2. **IDE API Churn**: Each IDE updates their extension API frequently. Breakage across multiple IDEs would be constant.

3. **Discovery Problem**: Users must:
   - Find the right extension for their IDE
   - Install CLI separately
   - Install extension separately
   - Configure both to work together

4. **MCP is Standard**: As of 2025, all major AI IDEs support MCP:
   - Claude Code ✅
   - GitHub Copilot ✅
   - Cursor ✅
   - Windsurf/Codeium ✅

5. **Future-Proof**: New AI IDEs will likely support MCP, not custom APIs.

**Final Decision:** Build MCP server (post-MVP). One implementation works across all IDEs. Standard protocol, maintained by Anthropic.

---

### Alternative 6: JSON Array for Job Queue

**What it was:**
Store the job queue as a standard JSON array:

```json
[
  {"type": "track-commit", "commit": {...}},
  {"type": "track-commit", "commit": {...}}
]
```

**Why it seemed appealing:**
- Standard JSON format
- Easy to parse with `JSON.parse()`
- Built-in validation
- Can use existing JSON tools

**Why we rejected it:**

1. **Not Atomic**: Adding a job requires:
   ```javascript
   const jobs = JSON.parse(fs.readFileSync('queue.json'));
   jobs.push(newJob);
   fs.writeFileSync('queue.json', JSON.stringify(jobs));
   ```
   If two git hooks run simultaneously, one could be lost.

2. **Requires Locking**: Would need a separate lock file just to append to queue, adding complexity.

3. **Read-Modify-Write**: Must read entire file, modify in memory, write back. Inefficient for large queues.

4. **Corruption Risk**: If process crashes during write, entire queue file is corrupted.

**JSONL Alternative:**
```javascript
// Append is atomic - no lock needed
fs.appendFileSync('queue.jsonl', JSON.stringify(newJob) + '\n');

// Read line-by-line
const jobs = fs.readFileSync('queue.jsonl', 'utf8')
  .split('\n')
  .filter(Boolean)
  .map(line => JSON.parse(line));
```

**Final Decision:** JSONL (JSON Lines) format. Atomic appends, no locking needed for enqueue, simple line-by-line parsing.

---

### Alternative 7: Opt-In Default Mode

**What it was:**
By default, track NO commits unless explicitly marked with `COMMITKIT_TRACK=1`:

```bash
# Default: not tracked
git commit -m "Work"

# Must explicitly track
COMMITKIT_TRACK=1 git commit -m "Important work"
```

**Why it seemed appealing:**
- Privacy-first approach
- No accidental tracking of sensitive work
- Forces user to think about what to track
- Better for shared/work repositories

**Why we rejected it:**

1. **High Friction**: Users must remember to set env var for every commit they want tracked. This creates constant friction.

2. **Adoption Killer**: Most users install CommitKit specifically to track commits automatically. If nothing is tracked by default, they'll think it's broken.

3. **Violates Expectations**: When someone runs `commitkit init`, they expect commits to start being tracked. Opt-in mode violates this expectation.

4. **Better Solutions Exist**: For sensitive repos, users can:
   - Simply not run `commitkit init` in those repos
   - Use `COMMITKIT_SKIP=1` for specific commits
   - Add patterns to `.commitkit-ignore`
   - Choose opt-in mode during init (still available as option)

5. **Power Users Can Choose**: During `commitkit init`, we ask the user which mode they want. Power users who want opt-in can select it explicitly.

**Final Decision:** Opt-out is default (track all commits). Users can choose opt-in during `commitkit init` if they prefer. Best of both worlds.

---

### Alternative 8: Message Prefix Skip Markers

**What it was:**
Skip commits by requiring a prefix in the commit message itself:

```bash
# Tracked
git commit -m "Add feature"

# Skipped
git commit -m "[skip] Experimental work"
git commit -m "PRIVATE: Test credentials"
```

**Why it seemed appealing:**
- Visible in git history (no hidden state)
- Works with any git client/GUI
- Easy to understand
- Industry standard (like `[skip ci]`)

**Why we rejected it:**

1. **Pollutes Commit Messages**: Users complained this "pollutes" their git history. Commit messages are part of project documentation and shouldn't contain tool-specific markers.

2. **Cannot Edit After Commit**: What if you realize after committing that you want to skip it? Must amend commit to add prefix, which changes the hash.

3. **Inflexible**:
   - Can't skip by file pattern (e.g., all lock file commits)
   - Can't skip by branch (e.g., all `tmp/*` branches)
   - Can't skip by author (e.g., bot commits)
   - Can't skip by time (e.g., late-night experiments)

4. **Conflicts with Other Tools**: `[skip ci]` is already used by CI systems. Adding more prefixes creates conflict risk and confusion.

5. **Better Alternatives Available**:
   - Environment variables (no message pollution)
   - Git notes (metadata, not part of message)
   - `.commitkit-ignore` (powerful pattern matching)

**Final Decision:** Three-layer system (env vars, git notes, ignore file) that doesn't pollute commit messages. Message content is still available as ONE pattern in `.commitkit-ignore` if users want it.

---

### Alternative 9: Local LLM Priority

**What it was:**
Prioritize local LLMs (Ollama, LM Studio, etc.) over IDE-integrated AI assistants:

1. Ollama (local)
2. LM Studio (local)
3. Claude Code (IDE)
4. GitHub Copilot (IDE)

**Why it seemed appealing:**
- No API costs (fully local)
- Works offline
- Privacy-first (data never leaves machine)
- No rate limits

**Why we rejected it:**

1. **Quality Gap**: Local models (even Llama 3) are significantly worse than Claude 3.5 Sonnet or GPT-4 for code analysis and summarization.

2. **Setup Burden**: Most developers don't have Ollama/LM Studio installed. Requiring this for CommitKit adds significant setup friction.

3. **Resource Usage**: Running local LLMs consumes significant RAM (8-16GB) and CPU. Most developers don't want this running while coding.

4. **IDE AI is Already Paid For**: Most developers already pay for:
   - GitHub Copilot ($10-20/month)
   - Claude Code (free or subscription)
   - Cursor ($20/month)
   These are better models and already authenticated.

5. **MCP Makes IDE Integration Easy**: With MCP server, we can leverage existing IDE AI with minimal code.

**Final Decision:** Prioritize IDE-integrated AI (Claude Code, Copilot, Cursor) first. Local LLMs as fallback for users who have them. Build MCP server to make IDE integration simple.

---

### Alternative 10: Immediate Inline Processing (No Background Worker)

**What it was:**
Process commits immediately in the git hook, blocking until complete:

```javascript
// In post-commit hook
const commitData = extractCommitData();
const analysis = await analyzeWithLLM(commitData);  // Blocks 5-30 seconds
await sendToAPI(commitData, analysis);
console.log('✅ Commit tracked');
```

**Why it seemed appealing:**
- Simpler architecture (no queue, no worker)
- Immediate feedback
- No job queue to manage
- Easier to debug (synchronous flow)

**Why we rejected it:**

1. **Unacceptable Terminal Blocking**: LLM analysis takes 5-30 seconds. Blocking the terminal after every commit is unacceptable UX:
   ```bash
   $ git commit -m "Fix bug"
   [waiting... waiting... 15 seconds pass...]
   ✅ Commit tracked
   $ # User has been waiting, getting frustrated
   ```

2. **Breaks Rapid Commit Workflows**: Many developers make multiple quick commits:
   ```bash
   git commit -m "WIP"                    # Blocks 10 seconds
   git commit -m "Fix tests"              # Blocks 10 seconds
   git commit -m "Clean up"               # Blocks 10 seconds
   # 30 seconds wasted, workflow destroyed
   ```

3. **Network Dependency**: If API is down or slow, commits are blocked. This breaks git, which is unacceptable.

4. **Offline Commits Impossible**: Can't make commits without internet, which breaks fundamental git workflow.

5. **LLM is Core Value**: User feedback was clear: "LLM integration is crucial for MVP." We can't skip it, but we also can't block commits for it.

**Final Decision:** Background worker is essential. Git hook queues commit in <100ms, worker processes later. Terminal never blocked, offline commits work, rapid workflows preserved.

---

## Summary of Decision Principles

Looking across all rejected alternatives, several principles emerge:

1. **Git is Sacred**: Never break or slow down core git workflows
2. **Respect User Intent**: When users delete commits from git, delete from API
3. **Simplicity Over Features**: Avoid complex tracking/relationships unless clear user value
4. **Standards Over Custom**: Use MCP instead of building custom integrations
5. **Privacy by Default**: Don't automatically modify user config files
6. **Quality Over Cost**: Prioritize better models (IDE AI) over cheaper ones (local)
7. **Progressive Enhancement**: Core functionality works without LLM, LLM enhances it
8. **Fail Silently**: Never block commits due to CommitKit errors

These principles guided our architecture decisions and should guide future enhancements.

---

## Next Steps

1. ✅ Document architecture decisions (this file)
2. ✅ Document alternatives and rejections (this section)
3. ⏳ Create Trello CSV from this document
4. ⏳ Implement background worker
5. ⏳ Implement comprehensive filtering
6. ⏳ Add LLM detection
7. ⏳ Write integration tests
8. ⏳ Setup cross-platform CI
9. ⏳ Beta test with real users
10. ⏳ Publish to npm

---

End of CLI Architecture Notes.
