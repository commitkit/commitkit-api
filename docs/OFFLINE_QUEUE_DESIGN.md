# Offline Queue Design Document

## Overview

CommitKit's offline queue system allows commits to be tracked even when the network is unavailable. Queued commits are automatically batched and synced when connectivity is restored.

## Core Design Principles

1. **Non-blocking** - Current commits always proceed regardless of queue state
2. **Explicit retry** - Users trigger queue processing with `commitkit queue sync`
3. **Visibility** - Queue status shown when non-empty
4. **Per-repository** - Each repository maintains its own queue
5. **Smart batching** - Use batch API endpoints to minimize network requests
6. **Dead letter queue** - Failed commits eventually move to DLQ for manual review

---

## Architecture

### Queue Storage

**Location:** `~/.commitkit/queues/<repo-hash>.json`

**Structure:**
```json
{
  "repository_url": "https://github.com/user/repo.git",
  "commits": [
    {
      "commit_hash": "abc123def456",
      "message": "Add feature X\n\nDetailed description...",
      "summary": "Add feature X",
      "committed_at": "2025-11-03T10:30:00Z",
      "queued_at": "2025-11-03T10:30:05Z",
      "attempts": 1,
      "last_error": "Connection timeout",
      "last_attempt_at": "2025-11-03T10:30:05Z"
    }
  ]
}
```

**Why per-repo queues:**
- Maintains commit ordering within repository
- Easier to manage and reason about
- Survives repository deletion (stored in home directory)
- Allows parallel syncing of different repos

### Dead Letter Queue (DLQ)

**Location:** `~/.commitkit/queues/<repo-hash>.dlq.json`

**Structure:**
```json
{
  "repository_url": "https://github.com/user/repo.git",
  "commits": [
    {
      "commit_hash": "abc123",
      "message": "...",
      "summary": "...",
      "committed_at": "2025-10-20T10:00:00Z",
      "queued_at": "2025-10-20T10:00:05Z",
      "moved_to_dlq_at": "2025-11-03T15:00:00Z",
      "total_attempts": 5,
      "last_error": "Validation failed: Message can't be blank",
      "reason": "max_attempts_exceeded"
    }
  ]
}
```

**Reasons for DLQ:**
- `max_attempts_exceeded` - After 5 failed sync attempts
- `stale` - After 14 days in regular queue
- `validation_error` - Non-network errors that won't resolve

**DLQ Behavior:**
- DLQ commits don't block regular queue processing
- Requires explicit action to retry: `commitkit queue dlq retry`
- Can be cleared manually: `commitkit queue dlq clear`

### Lockfile Strategy

**Location:** `~/.commitkit/queues/<repo-hash>.lock`

**Purpose:** Prevent race conditions when multiple terminal sessions access the same queue

**Implementation:**
```ruby
# Pseudocode
File.open(lock_file, File::RDWR|File::CREAT, 0644) do |f|
  f.flock(File::LOCK_EX)  # Exclusive lock
  # Read/write queue
  f.flock(File::LOCK_UN)  # Unlock
end
```

**Timeout:** 5 seconds - if lock can't be acquired, show warning and skip

---

## Database Schema Changes

### Add Timestamp Fields to Commits

**Current state:**
- ✅ `created_at` - Rails automatic (when database record created)
- ✅ `updated_at` - Rails automatic (when record last updated)
- ❌ `committed_at` - **MISSING** (when git commit was made)
- ❌ `synced_at` - **MISSING** (when commit synced to server)

**Migration needed:**
```ruby
class AddTimestampsToCommits < ActiveRecord::Migration[8.1]
  def change
    add_column :commits, :committed_at, :datetime, null: false
    add_column :commits, :synced_at, :datetime

    # Backfill existing records
    reversible do |dir|
      dir.up do
        # For existing commits, use created_at as both committed_at and synced_at
        execute <<-SQL
          UPDATE commits
          SET committed_at = created_at, synced_at = created_at
          WHERE committed_at IS NULL
        SQL
      end
    end
  end
end
```

**Field meanings:**
- `committed_at` - When the git commit was actually made (from `git log`, sent by CLI)
- `synced_at` - When the commit was successfully synced to CommitKit server (set by API)
- `created_at` - Rails automatic timestamp (when database record created, essentially same as synced_at)
- `updated_at` - Rails automatic timestamp (when record last updated)

**Why we need both committed_at AND synced_at:**
- `committed_at` preserves git history timeline (authoritative source of truth)
- `synced_at` tracks when we received the commit (useful for debugging sync issues)
- For online commits: `committed_at` ≈ `synced_at` ≈ `created_at`
- For offline commits: `committed_at` < `synced_at` ≈ `created_at`

**Usage:**
- Dashboard sorts by `committed_at` (shows commits in git chronological order)
- Can display "Synced X ago" using `synced_at`
- Can track sync lag: `synced_at - committed_at` shows how long commit was queued
- Offline commits will have `committed_at` < `synced_at` (committed while offline, synced later)

---

## API Changes

### New Endpoint: PATCH /api/v1/repositories/:id/commits

**Purpose:** Add new commits to existing repository without deleting old ones

**Request:**
```json
{
  "commits": [
    {
      "commit_hash": "abc123",
      "message": "...",
      "summary": "...",
      "committed_at": "2025-11-03T10:30:00Z"
    }
  ]
}
```

**Response:**
```json
{
  "synced": 5,
  "skipped": 2,
  "failed": 0,
  "errors": []
}
```

**Behavior:**
- Adds commits to repository (identified by repository URL in auth context)
- Skips duplicates based on commit_hash
- Sets `synced_at` to current time (when record created)
- Returns summary of operation
- Does NOT delete existing commits (unlike POST with full resync)

---

## User Experience

### Happy Path: Network Available

```bash
$ git commit -m "Add feature"
[main abc123] Add feature
✓ Synced to CommitKit
```

### Network Unavailable: Queue Commit

```bash
$ git commit -m "Add feature"
[main abc123] Add feature
⚠️  Network unavailable. Commit queued for retry (1 pending)
💡 Run 'commitkit queue sync' when online
```

### Subsequent Commits Show Queue Status

```bash
$ git commit -m "Another feature"
[main def456] Another feature
⚠️  Network unavailable. Commit queued for retry (2 pending)
💡 Run 'commitkit queue sync' when online
```

### Manual Sync

```bash
$ commitkit queue sync
Syncing 2 queued commits...
✓ Synced commit abc123
✓ Synced commit def456
✓ Successfully synced 2 commits
```

### Commit Moved to DLQ

```bash
$ commitkit queue sync
⚠️  Commit abc123 failed 5 times. Moving to dead letter queue.
💡 Review with 'commitkit queue dlq list'

Synced: 3 commits
Failed: 0 commits
Moved to DLQ: 1 commit
```

### Check Queue Status

```bash
$ commitkit queue status
Repository: https://github.com/user/repo.git
Queued commits: 3
Oldest queued: 2 hours ago (commit abc123)
Last attempt: 5 minutes ago (failed: Connection timeout)

$ commitkit queue list
1. abc123 - "Add feature" (queued 2 hours ago, 3 attempts)
2. def456 - "Another feature" (queued 1 hour ago, 2 attempts)
3. ghi789 - "Fix bug" (queued 30 minutes ago, 1 attempt)
```

### DLQ Management

```bash
$ commitkit queue dlq list
Dead Letter Queue for https://github.com/user/repo.git

1. abc123 - "Fix bug"
   Reason: Max attempts exceeded (5 failures)
   Last error: Connection timeout
   In DLQ since: 2 hours ago

2. def456 - "Add feature"
   Reason: Stale (14+ days in queue)
   Last error: Network unreachable
   In DLQ since: 1 day ago

$ commitkit queue dlq status
Repository: https://github.com/user/repo.git
DLQ commits: 2
Oldest: 1 day ago

$ commitkit queue dlq retry abc123
Retrying commit abc123...
✓ Successfully synced commit abc123
✓ Removed from DLQ

$ commitkit queue dlq retry --all
Retrying 2 DLQ commits...
✓ Synced commit abc123
✗ Failed commit def456 (moved back to DLQ)
Results: 1 synced, 1 failed
```

### Clear Queue (Manual)

```bash
$ commitkit queue clear
⚠️  This will remove 3 queued commits. Continue? (y/N) y
✓ Queue cleared

$ commitkit queue dlq clear
⚠️  This will permanently remove 2 commits from DLQ. Continue? (y/N) y
✓ DLQ cleared
```

---

## CLI Commands

### Regular Queue Commands

| Command | Description |
|---------|-------------|
| `commitkit queue status` | Show queue summary for current repo |
| `commitkit queue list` | List all queued commits with details |
| `commitkit queue sync` | Attempt to sync all queued commits |
| `commitkit queue clear` | Remove all queued commits (with confirmation) |

### Dead Letter Queue Commands

| Command | Description |
|---------|-------------|
| `commitkit queue dlq status` | Show DLQ summary for current repo |
| `commitkit queue dlq list` | List all DLQ commits with details |
| `commitkit queue dlq retry [hash]` | Retry specific commit or all with --all |
| `commitkit queue dlq clear` | Permanently remove all DLQ commits |
| `commitkit queue dlq remove <hash>` | Remove specific commit from DLQ |

### Flags

| Flag | Description |
|------|-------------|
| `--all` | Operate on queues for all repositories |
| `--force` | Skip confirmation prompts |

**Examples:**
```bash
# Sync all repos
commitkit queue sync --all

# Clear without confirmation
commitkit queue clear --force

# Show status for all repos
commitkit queue status --all

# Retry all DLQ commits
commitkit queue dlq retry --all
```

---

## Error Handling

### Error Classification

**Network Errors (queue commit):**
- Connection timeout
- DNS resolution failure
- Connection refused
- SSL/TLS errors
- HTTP 502, 503, 504

**Non-Network Errors (show immediately, don't queue):**
- HTTP 401 (authentication)
- HTTP 422 (validation)
- HTTP 404 (endpoint not found)
- Invalid API key format

**Validation Errors (move to DLQ immediately):**
- Message can't be blank
- Commit hash invalid format
- Data validation failures

### Retry Logic

**Move to DLQ after:**
- 5 failed sync attempts
- 14 days in regular queue
- Validation errors (immediately)

**Attempt Tracking:**
```ruby
commit.attempts += 1
commit.last_attempt_at = Time.now
commit.last_error = error_message

if commit.attempts >= 5
  move_to_dlq(commit, reason: "max_attempts_exceeded")
elsif (Time.now - commit.queued_at) > 14.days
  move_to_dlq(commit, reason: "stale")
end
```

---

## Queue Warnings

### Warning Thresholds

1. **Size warning:** 50+ commits
   ```
   ⚠️  Large queue: 52 commits pending. Consider running 'commitkit queue sync'
   ```

2. **Age warning:** 7+ days old
   ```
   ⚠️  Old queue: Oldest commit is 8 days old. Run 'commitkit queue sync'
   ```

3. **Both:**
   ```
   ⚠️  Queue needs attention: 52 commits (oldest: 8 days). Run 'commitkit queue sync'
   ```

4. **DLQ warning:**
   ```
   ⚠️  1 commit in dead letter queue. Run 'commitkit queue dlq list' to review
   ```

**When shown:**
- On every `git commit` (if queue non-empty)
- On `commitkit queue status`
- On CLI startup (if interactive)

---

## Batch Syncing Strategy

### When to Batch

**Batch size:** All queued commits in a single API call

**Why batch all:**
- Minimize network roundtrips
- Atomic success/failure handling
- Server can optimize database operations
- Simpler client code

**Batch endpoint:** `PATCH /api/v1/repositories/:id/commits`

### Batch Processing Flow

```
1. Read queue file (with lock)
2. Prepare batch request with all commits
3. Send PATCH /api/v1/repositories/:id/commits
4. Process response:
   - synced: remove from queue
   - skipped: remove from queue (already exists)
   - failed: update attempt count, keep in queue or move to DLQ
5. Write updated queue (with lock)
6. Show summary to user
```

### Partial Failure Handling

If batch API returns some failures:
```json
{
  "synced": 8,
  "skipped": 2,
  "failed": 2,
  "errors": [
    {
      "commit_hash": "abc123",
      "errors": ["Message can't be blank"]
    }
  ]
}
```

**Client behavior:**
- Remove synced and skipped commits from queue
- Update failed commits (increment attempts, update last_error)
- Move to DLQ if threshold reached (5 attempts or validation error)
- Show user what succeeded and what failed

---

## Edge Cases & Solutions

### 1. Clock Skew
**Problem:** Queued commits might have `committed_at` timestamps newer than commits made while offline

**Solution:** Accept out-of-order timestamps
- Database stores commits with their original `committed_at` timestamp
- Dashboard sorts by `committed_at` regardless of sync order
- Git history is authoritative, not sync order

**Example:**
```
Day 1 (online): Commit A (committed_at: Nov 1, synced_at: Nov 1)
Day 2 (offline): Commit B (committed_at: Nov 2, queued)
Day 3 (offline): Commit C (committed_at: Nov 3, queued)
Day 4 (online): Commit D (committed_at: Nov 4, synced_at: Nov 4)
Day 5 (sync queue): Commit B & C (committed_at: Nov 2 & 3, synced_at: Nov 5)

Dashboard order: A, B, C, D (sorted by committed_at)
All timestamps preserved correctly!
```

**Not a blocker:** Git history is still correct, only sync order affected

### 2. Repository URL Changes
**Problem:** Remote URL changes (e.g., repo renamed, transferred)

**Detection:**
```bash
# Old queue has: https://github.com/user/old-name.git
# Current remote: https://github.com/user/new-name.git
```

**Solution:** Prompt user to reconcile
```
⚠️  Repository URL mismatch detected!
    Queue: https://github.com/user/old-name.git
    Current: https://github.com/user/new-name.git

Options:
  1. Clear queue and resync (recommended)
  2. Migrate queue to new URL
  3. Ignore (keep separate queues)

Choice (1-3):
```

**Recommended action:** Clear and resync
```bash
commitkit queue clear && commitkit sync --delete-all-and-resync
```

**Future enhancement:** Auto-detect GitHub repo renames via API

### 3. Large Queues (100+ commits)
**Problem:** Large queues slow down user workflow if checked on every commit

**Current solution:**
- Queue check is fast (single file read)
- Warnings only shown if non-empty
- Sync is explicit (user-triggered)

**Future solution (MCP Server):**
- Background process handles queue independently
- Non-blocking async retry with exponential backoff
- Terminal shows live updates via MCP protocol
- Queue processing doesn't block git workflow

**MCP Integration Plan:**
```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│   Terminal  │         │ MCP Server  │         │ CommitKit   │
│   (Client)  │────────>│ (Background)│────────>│  API        │
└─────────────┘         └─────────────┘         └─────────────┘
      │                        │
      │  git commit            │
      │  (queue commit)        │
      │                        │
      │                        │ (auto-sync with backoff)
      │<───────────────────────│
      │  (status updates)      │
```

**MCP Benefits:**
- Non-blocking queue processing
- Real-time status updates
- Automatic retry with smart backoff
- Shared state across terminal sessions
- Better resource management

### 4. Concurrent Access (Multiple Terminal Sessions)
**Problem:** Two terminals committing to same repo simultaneously

**Solution:** Lockfile-based concurrency control

```ruby
# Simplified implementation
def with_queue_lock(repo_hash, &block)
  lock_file = File.join(queue_dir, "#{repo_hash}.lock")

  File.open(lock_file, File::RDWR|File::CREAT, 0644) do |f|
    acquired = f.flock(File::LOCK_EX | File::LOCK_NB)

    if acquired
      yield
      f.flock(File::LOCK_UN)
    else
      # Timeout after 5 seconds
      Timeout.timeout(5) do
        f.flock(File::LOCK_EX)
        yield
        f.flock(File::LOCK_UN)
      end
    end
  rescue Timeout::Error
    puts "⚠️  Could not acquire queue lock. Another process may be using it."
    exit 1
  end
end
```

**Behavior:**
- First terminal acquires exclusive lock
- Second terminal waits up to 5 seconds
- After timeout, shows warning and exits gracefully
- Prevents corrupted queue files

---

## Implementation Phases

### Phase 1: Basic Queue (MVP)
- [ ] Queue storage structure
- [ ] Lockfile concurrency control
- [ ] `commitkit queue` commands (status, list, sync, clear)
- [ ] Network error detection
- [ ] Queue commit on failure
- [ ] Batch sync endpoint (PATCH /api/v1/repositories/:id/commits)
- [ ] Add `committed_at` field to commits table
- [ ] Update CLI to send `committed_at` from git log

### Phase 2: Dead Letter Queue
- [ ] DLQ storage structure
- [ ] Move to DLQ after 5 attempts
- [ ] Move to DLQ after 14 days
- [ ] Move to DLQ for validation errors
- [ ] `commitkit queue dlq` commands
- [ ] DLQ warnings on commit

### Phase 3: Enhanced UX
- [ ] Size/age warnings
- [ ] Repository URL mismatch detection
- [ ] Better error messages
- [ ] Queue count in output
- [ ] `--all` flag for cross-repo operations

### Phase 4: MCP Server (Future)
- [ ] Background queue processing
- [ ] Automatic retry with exponential backoff
- [ ] Real-time status updates
- [ ] Cross-session state management

---

## Testing Strategy

### Unit Tests
- Queue file read/write
- Lockfile acquisition/release
- Error classification (network vs non-network vs validation)
- Batch request building
- Partial failure handling
- DLQ move logic (attempts, age, validation)
- Timestamp handling (committed_at vs synced_at)

### Integration Tests
- Full offline → queue → sync flow
- Concurrent access from multiple processes
- Large queue performance (100+ commits)
- Repository URL migration
- DLQ retry flow
- Clock skew scenarios (offline commits with old timestamps)

### Manual Testing Scenarios
1. Turn off WiFi, make commits, turn on WiFi, sync
2. Run two terminals simultaneously committing to same repo
3. Queue 100+ commits and measure sync performance
4. Change repository remote URL with pending queue
5. Test queue with very old commits (7+ days)
6. Force commit to fail 5+ times to trigger DLQ
7. Make commits while offline with system clock changes

---

## Configuration

### Environment Variables

```bash
# Queue directory (default: ~/.commitkit/queues)
COMMITKIT_QUEUE_DIR=~/custom/queue/path

# Queue size warning threshold (default: 50)
COMMITKIT_QUEUE_SIZE_WARNING=100

# Queue age warning threshold in days (default: 7)
COMMITKIT_QUEUE_AGE_WARNING=14

# DLQ max attempts threshold (default: 5)
COMMITKIT_DLQ_MAX_ATTEMPTS=10

# DLQ stale threshold in days (default: 14)
COMMITKIT_DLQ_STALE_DAYS=30

# Lock timeout in seconds (default: 5)
COMMITKIT_LOCK_TIMEOUT=10
```

### Config File (~/.commitkit/config.yml)

```yaml
queue:
  directory: ~/.commitkit/queues
  warnings:
    size_threshold: 50
    age_threshold_days: 7
  dlq:
    max_attempts: 5
    stale_threshold_days: 14
  lock_timeout_seconds: 5
  auto_retry: false  # Future: enable background retry
```

---

## Security Considerations

### API Key Storage
- Queue files contain commit data but NOT API keys
- API key stays in separate config file
- Queue files readable only by user (0600 permissions)

### File Permissions
```bash
# Queue files
chmod 600 ~/.commitkit/queues/*.json

# DLQ files
chmod 600 ~/.commitkit/queues/*.dlq.json

# Lock files
chmod 600 ~/.commitkit/queues/*.lock

# Queue directory
chmod 700 ~/.commitkit/queues
```

### Data Privacy
- Queue stored locally only
- No cloud sync of queue (commits sync when online)
- User can clear queue anytime
- DLQ can be permanently cleared

---

## Metrics & Observability

### Metrics to Track (Future)
- Average queue size over time
- Queue sync success rate
- Average time from queue → sync
- Network failure frequency
- Largest queue size observed
- DLQ size over time
- DLQ retry success rate

### Logging
```ruby
# Queue operations logged to ~/.commitkit/logs/queue.log
[2025-11-03 10:30:05] INFO: Queued commit abc123 (network timeout)
[2025-11-03 10:35:10] INFO: Sync attempt 1/5 for abc123
[2025-11-03 10:35:12] SUCCESS: Synced commit abc123
[2025-11-03 11:00:00] WARN: Moving commit def456 to DLQ (max attempts exceeded)
```

---

## FAQ

**Q: What happens if I delete the queue file manually?**
A: Queue is lost, but git history is intact. Commits can be resynced with `--delete-all-and-resync`.

**Q: Can I edit queued commits before sync?**
A: Not directly. You can clear the queue and resync, or manually push specific commits via API.

**Q: What if my repo has 1000+ commits queued?**
A: Batch API handles it, but may be slow. Consider MCP server for better UX. Warning shown at 50+.

**Q: Does queue sync maintain commit order?**
A: Yes, queue processes commits in the order they were made (FIFO).

**Q: What if batch API has size limits?**
A: Current implementation batches all. Future: could chunk into batches of 100 if needed.

**Q: Can I sync queue from a different directory?**
A: Queue is tied to repository URL (hash), not local path. Works from any clone of same repo.

**Q: What's the difference between committed_at and synced_at?**
A: `committed_at` is when you made the git commit. `synced_at` (aka `created_at`) is when it was saved to CommitKit. They differ for offline commits.

**Q: Why does my commit show "committed 3 days ago" but "synced 1 hour ago"?**
A: You made the commit 3 days ago while offline. It was queued and just synced 1 hour ago.

**Q: Can I retry just one DLQ commit?**
A: Yes! `commitkit queue dlq retry <commit_hash>`

**Q: What happens to DLQ commits if I never retry them?**
A: They stay in DLQ indefinitely. You can review and clear them anytime.

---

## Open Questions

1. **Batch size limits:** Should we chunk large queues (100+ commits) into multiple requests?
   - **Decision:** Start with single batch, add chunking if API limits encountered

2. **Queue migration:** How to handle queue format changes in future versions?
   - **Decision:** Add version field to queue JSON, write migration code as needed

3. **DLQ auto-cleanup:** Should very old DLQ commits (90+ days) be auto-removed?
   - **Decision:** No auto-removal, but show prominent warning to user

4. **Cross-repo queue visibility:** Should `commitkit status` show all repo queues by default?
   - **Decision:** Show current repo by default, add `--all` flag for cross-repo visibility

---

## Success Metrics

**Phase 1 Success Criteria:**
- [ ] Commits successfully queued when offline
- [ ] Queued commits sync correctly when online
- [ ] No data loss (queue survives crashes, reboots)
- [ ] Clear UX (users know what's happening)
- [ ] Concurrent access works (no corrupted queues)
- [ ] `committed_at` and `synced_at` timestamps correct

**Phase 2 Success Criteria (DLQ):**
- [ ] Failed commits move to DLQ after threshold
- [ ] DLQ commands work correctly
- [ ] Users can retry/clear DLQ commits
- [ ] Warnings shown for non-empty DLQ

**Phase 3 Success Criteria (Enhanced UX):**
- [ ] Users warned about stale/large queues
- [ ] Repository URL changes handled gracefully
- [ ] Error messages actionable and clear

**Phase 4 Success Criteria (MCP):**
- [ ] Queue processing doesn't block terminal
- [ ] Automatic retry with smart backoff
- [ ] Real-time status updates
- [ ] Works across multiple terminal sessions

---

## Related Documents

- [API Documentation](API.md)
- [CLI Command Reference](CLI_REFERENCE.md)
- [Architecture Overview](ARCHITECTURE.md)
- [MCP Server Design](MCP_SERVER_DESIGN.md) _(future)_

---

**Document Version:** 1.0
**Last Updated:** 2025-11-03
**Authors:** Richie Thomas, Claude (Anthropic)
**Status:** Shelved (Feature deferred due to complexity)

---

# Appendix: Design Review Discussion

**Note to readers:** What follows is a comprehensive devil's advocate PR review exercise conducted between a hypothetical developer (proposing this feature) and a senior engineer reviewer. This 30-round back-and-forth explores edge cases, potential issues, and design trade-offs. The discussion reveals significant complexity that led to shelving this feature for now, but the insights are preserved here for future reference when we're ready to revisit offline queue support.

The format alternates between Developer (👨‍💻) and Reviewer (🔎) perspectives, surfacing important considerations about concurrency, error handling, user experience, security, testing, and performance.

---

## Round 1

**👨‍💻 Developer:**
Hey team! I've written up a comprehensive design doc for our offline queue feature. This will allow users to make commits while offline and sync them later. The doc covers queue storage, DLQ, API changes, and a phased implementation plan. Ready for review!

**🔎 Reviewer:**
Thanks for this! Initial reaction: this is very thorough. But I'm immediately concerned about the complexity. You're proposing:
- Regular queue files
- Dead letter queue files
- Lockfiles
- New database fields
- New API endpoint
- 15+ new CLI commands

For an MVP, this seems like a lot. Can we simplify? What's the absolute minimum we need to ship something useful?

---

## Round 2

**👨‍💻 Developer:**
Fair point! Looking at it again, here's what I think we could defer:

**MVP (Phase 1):**
- Basic queue storage
- Network error detection
- `commitkit queue sync` command
- Simple batch endpoint

**Defer to Phase 2:**
- Dead letter queue (DLQ)
- All the `dlq` subcommands
- Repository URL migration detection
- MCP server integration

The DLQ is nice-to-have but not critical - users can always manually `queue clear` and resync. Thoughts?

**🔎 Reviewer:**
Better! But I still have concerns. Let's talk about the lockfile approach. You're using `flock` with a 5-second timeout. What happens in these scenarios:

1. User's terminal crashes while holding the lock
2. User has 3 terminals open, all trying to commit simultaneously
3. Lock file gets corrupted or has wrong permissions

Have you considered using atomic file operations instead of locks?

---

## Round 3

**👨‍💻 Developer:**
Good catches! Let me address each:

1. **Terminal crash:** `flock` is automatically released by the OS when the process dies, so stale locks aren't an issue
2. **3 terminals:** They'll queue up - first gets lock, second waits, third waits. Max 5-second wait per terminal
3. **Corrupted lock file:** We create it with 0644 permissions. If corrupted, we could fall back to atomic rename operations

You mentioned atomic operations - are you thinking something like:
```ruby
# Write to temp file, then atomic rename?
File.write("#{queue_file}.tmp", data)
File.rename("#{queue_file}.tmp", queue_file)
```

The problem is this doesn't prevent concurrent reads/writes between processes. We still need coordination. What did you have in mind?

**🔎 Reviewer:**
You're right that atomic rename doesn't solve concurrency. I was thinking we could use it WITH a lock-free algorithm, but that gets complex fast.

Actually, your `flock` approach is probably fine for MVP. But let's add:
- Better error messages when lock timeout occurs
- Log which PID holds the lock (for debugging)
- Advice to user: "Another CommitKit process is running. Wait or kill it."

My bigger concern now is the database migration. You're adding `committed_at` as `null: false`, but then backfilling with `created_at`. What happens if the backfill fails partway through due to some bad data? The migration will be stuck.

---

## Round 4

**👨‍💻 Developer:**
Great point about the migration! Let me revise:

```ruby
class AddTimestampsToCommits < ActiveRecord::Migration[8.1]
  def change
    # Add as nullable first
    add_column :commits, :committed_at, :datetime
    add_column :commits, :synced_at, :datetime

    # Backfill in batches
    reversible do |dir|
      dir.up do
        Commit.in_batches(of: 1000) do |batch|
          batch.update_all('committed_at = created_at, synced_at = created_at')
        end
      end
    end

    # Then add NOT NULL constraint
    change_column_null :commits, :committed_at, false
  end
end
```

This way:
- Add column as nullable
- Backfill in batches (won't blow up memory)
- Then add NOT NULL constraint
- If backfill fails, we can fix data and re-run

Better?

**🔎 Reviewer:**
Much better! The batching is good. Though I'd use `find_each` instead of `in_batches` since you're doing updates:

```ruby
Commit.find_each(batch_size: 1000) do |commit|
  commit.update_columns(
    committed_at: commit.created_at,
    synced_at: commit.created_at
  )
end
```

Wait, actually that's slower (N+1 updates). Your `update_all` is better. Stick with that.

Now let's talk about the API. You're proposing `PATCH /api/v1/repositories/:id/commits` for batch adding. But how do we identify the repository? By ID? What if the CLI doesn't know the repository ID yet (first time syncing)?

---

## Round 5

**👨‍💻 Developer:**
Ah, you've identified a real issue! The CLI won't know the repository database ID. Let me think through the flow:

**Current flow (online sync):**
1. CLI extracts repo URL from `git config`
2. CLI sends commits to `POST /api/v1/repositories` with `url` and `commits` array
3. API finds or creates repository by URL
4. API creates commits

**Proposed queue sync flow:**
1. Queue has commits for `https://github.com/user/repo.git`
2. CLI needs to sync them...
3. But to which endpoint?

I think we need to change the batch endpoint to:

```
PATCH /api/v1/repositories/by-url
Body: {
  "url": "https://github.com/user/repo.git",
  "commits": [...]
}
```

Or reuse the existing `POST /api/v1/repositories` endpoint and have it handle both create AND append operations. Thoughts?

**🔎 Reviewer:**
I like reusing the existing endpoint! Make it idempotent:

```
POST /api/v1/repositories
Body: {
  "url": "https://github.com/user/repo.git",
  "commits": [...],
  "sync_mode": "append"  // or "replace" (default)
}
```

- `sync_mode: "replace"` - Current behavior (delete all, resync)
- `sync_mode: "append"` - Add commits, skip duplicates

This way:
- No new endpoint needed
- Consistent API surface
- Queue sync just uses `append` mode

But wait - looking at your design doc, you mention batch API returning `{synced, skipped, failed}`. What if someone sends 100 commits and 50 fail due to validation? Do we partially succeed? How does the client know which ones to retry?

---

## Round 6

**👨‍💻 Developer:**
Excellent question! The response includes error details:

```json
{
  "synced": 48,
  "skipped": 2,
  "failed": 50,
  "errors": [
    {
      "commit_hash": "abc123",
      "errors": ["Message can't be blank"]
    },
    // ... 49 more
  ]
}
```

The client can then:
1. Remove synced commits from queue (by commit_hash)
2. Remove skipped commits from queue (already exist)
3. Keep failed commits in queue, update their attempt count
4. Match failed commits by commit_hash from errors array

This means we need to track `commit_hash` in queue file (already in the design). The client logic would be:

```ruby
response = api.batch_sync(commits)

response.errors.each do |error|
  commit = queue.find { |c| c.commit_hash == error.commit_hash }
  commit.attempts += 1
  commit.last_error = error.errors.join(", ")
end

queue.reject! { |c| response.synced_hashes.include?(c.commit_hash) }
queue.reject! { |c| response.skipped_hashes.include?(c.commit_hash) }
```

Does this make sense?

**🔎 Reviewer:**
It makes sense, but the API response doesn't include `synced_hashes` or `skipped_hashes` arrays - just counts. We need to add those:

```json
{
  "synced": 48,
  "synced_hashes": ["abc123", "def456", ...],
  "skipped": 2,
  "skipped_hashes": ["ghi789", "jkl012"],
  "failed": 50,
  "errors": [
    {
      "commit_hash": "mno345",
      "errors": ["Message can't be blank"]
    }
  ]
}
```

Otherwise the client has no way to know which specific commits succeeded.

Also, I'm concerned about transaction boundaries. If we're processing 100 commits and commit #50 raises an exception (not validation, but like a database deadlock), what happens? Do we lose all 100? Or do we commit each one individually?

---

## Round 7

**👨‍💻 Developer:**
Great catch on the response format! Yes, we absolutely need those hash arrays. Let me update the design doc with that.

For transaction boundaries, I'm thinking we should process each commit individually within its own transaction:

```ruby
def batch_create_commits(commits_data)
  results = { synced: [], skipped: [], errors: [] }

  commits_data.each do |commit_data|
    begin
      commit = repository.commits.find_by(commit_hash: commit_data[:commit_hash])

      if commit
        results[:skipped] << commit_data[:commit_hash]
      else
        repository.commits.create!(
          commit_hash: commit_data[:commit_hash],
          message: commit_data[:message],
          committed_at: commit_data[:committed_at],
          synced_at: Time.current
        )
        results[:synced] << commit_data[:commit_hash]
      end
    rescue ActiveRecord::RecordInvalid => e
      results[:errors] << {
        commit_hash: commit_data[:commit_hash],
        errors: e.record.errors.full_messages
      }
    end
  end

  results
end
```

This means:
- Each commit is its own transaction
- One failure doesn't blow up the whole batch
- We can process 100 commits, have 50 fail, and still save the other 50

Downside: slower (100 transactions vs 1). But more resilient. What do you think?

**🔎 Reviewer:**
I like the resilience! But you're right about performance. For MVP, individual transactions are fine. We can optimize later with batched inserts if it becomes a bottleneck.

One thing though - your rescue clause only catches `RecordInvalid`. What about:
- `ActiveRecord::RecordNotUnique` (duplicate hash despite our check)
- `PG::ConnectionBad` (database connection lost)
- `Timeout::Error` (database query timeout)

Should we catch all exceptions and treat them as "failed" for that commit? Or let some bubble up and fail the whole request?

---

## Round 8

**👨‍💻 Developer:**
Good distinction! I think we should categorize errors:

**Commit-level errors (add to results[:errors]):**
- `ActiveRecord::RecordInvalid` - validation failed
- `ActiveRecord::RecordNotUnique` - race condition on duplicate (treat as "skipped")

**Request-level errors (bubble up, fail whole request):**
- `PG::ConnectionBad` - database down (client should retry whole batch)
- `Timeout::Error` - database slow (client should retry whole batch)
- Authentication/authorization errors

Reasoning:
- Validation errors are per-commit, won't be fixed by retry
- Database errors affect all commits, should retry entire batch
- This way client doesn't lose track of what was attempted

So:

```ruby
rescue ActiveRecord::RecordInvalid => e
  results[:errors] << {...}
rescue ActiveRecord::RecordNotUnique
  results[:skipped] << commit_data[:commit_hash]
# Let other errors bubble up
```

Make sense?

**🔎 Reviewer:**
Yes, that makes sense! Though I'd add a catch-all for truly unexpected errors:

```ruby
rescue ActiveRecord::RecordInvalid => e
  results[:errors] << {...}
rescue ActiveRecord::RecordNotUnique
  results[:skipped] << commit_data[:commit_hash]
rescue StandardError => e
  # Log the error for debugging
  Rails.logger.error("Unexpected error processing commit #{commit_data[:commit_hash]}: #{e.message}")
  results[:errors] << {
    commit_hash: commit_data[:commit_hash],
    errors: ["Unexpected error: #{e.class.name}"]
  }
end
```

This way we degrade gracefully instead of 500-ing on weird edge cases.

Now let's talk about the queue file format. You're using JSON. What happens when:
1. User has 10,000 commits queued (large file)
2. User manually edits the JSON file
3. Queue file exists but is empty or corrupted

How do we handle these gracefully?

---

## Round 9

**👨‍💻 Developer:**
Let me address each:

**1. Large files (10K commits):**
- JSON parsing is fast enough for 10K records
- File size: ~10KB per commit × 10,000 = ~100MB (manageable)
- We warn at 50 commits, strongly warn at 100+
- If it becomes an issue, we can split into multiple queue files

**2. Manual edits:**
- Valid JSON → works fine
- Invalid JSON → rescue `JSON::ParserError`, show error, refuse to proceed
- User must fix or delete queue file

**3. Corrupted/empty file:**
```ruby
def load_queue
  return [] unless File.exist?(queue_file)

  content = File.read(queue_file)
  return [] if content.strip.empty?

  JSON.parse(content)
rescue JSON::ParserError => e
  raise QueueCorruptedError, "Queue file corrupted: #{e.message}. Please fix or run 'commitkit queue clear --force'"
end
```

We could also add a `commitkit queue validate` command to check file health. Thoughts?

**🔎 Reviewer:**
I like the validation idea! But I'm worried about the user experience when JSON is corrupted. Telling a user to "fix the JSON" is scary. What if we:

1. Automatically backup queue file before writing (keep last 3 backups)
2. If current queue is corrupted, try loading from backup
3. Show user: "Queue corrupted, restored from backup (2 minutes old). Lost: 1 commit"

This way we're more resilient to corruption without user intervention.

Also, you mentioned file size could reach 100MB for 10K commits. That seems high! Are you storing the full commit message in the queue? What if someone has a commit with a 1MB message (auto-generated file, huge paste, etc.)? Should we truncate messages in the queue?

---

## Round 10

**👨‍💻 Developer:**
Great point about backups! Let's add:

```ruby
def write_queue(data)
  with_lock do
    # Rotate backups
    rotate_backups if File.exist?(queue_file)

    # Write atomically
    temp_file = "#{queue_file}.tmp"
    File.write(temp_file, JSON.pretty_generate(data))
    File.rename(temp_file, queue_file)
  end
end

def rotate_backups
  # Keep last 3: queue.json.bak.1, .2, .3
  (2).downto(1) do |i|
    old = "#{queue_file}.bak.#{i}"
    new = "#{queue_file}.bak.#{i+1}"
    File.rename(old, new) if File.exist?(old)
  end
  FileUtils.cp(queue_file, "#{queue_file}.bak.1")
end
```

For message size - good catch! We should:
- Store full message in queue (we need it for syncing)
- But warn if queue file > 10MB: "Large queue file detected. Consider syncing."
- Don't truncate (we'd lose data)

The real solution is: don't let the queue grow that large. That's why we have aggressive warnings and DLQ.

**🔎 Reviewer:**
The backup rotation looks good! Though `File.copy` should be `FileUtils.cp` (Ruby doesn't have `File.copy`).

I'm still uneasy about storing full messages. Here's a scenario:
- User commits 100 times with massive auto-generated test data in messages
- Queue file balloons to 500MB
- Every commit now takes 2+ seconds just to parse the queue file
- User experience degrades severely

What if we compress the queue file? Use gzip compression for storage, decompress on read?

```ruby
require 'zlib'

def write_queue(data)
  json = JSON.generate(data)
  Zlib::GzipWriter.open(queue_file) do |gz|
    gz.write(json)
  end
end

def read_queue
  Zlib::GzipReader.open(queue_file) do |gz|
    JSON.parse(gz.read)
  end
end
```

This could reduce a 100MB file to ~10MB (10x compression for text is typical).

---

## Round 11

**👨‍💻 Developer:**
Compression is clever! But I have concerns:

**Pros:**
- Smaller files (10x compression)
- Faster I/O (less disk reads)

**Cons:**
- Can't manually inspect/edit queue (binary format)
- Corrupted gzip file is harder to recover from
- Adds dependency on zlib (though it's in stdlib)
- Loses the "simple JSON file" developer experience

**Alternative:** What if we keep JSON but add message size limits at queue time?

```ruby
def queue_commit(commit)
  if commit.message.bytesize > 1.megabyte
    warn "⚠️  Commit message very large (#{commit.message.bytesize / 1024}KB). Truncating for queue."
    commit.message = commit.message[0...1.megabyte] + "\n\n[Message truncated in queue]"
  end

  queue.add(commit)
end
```

Then document: "Queue truncates messages > 1MB. Sync online for full message preservation."

Thoughts? Or should we go with compression?

**🔎 Reviewer:**
Hmm, truncating messages is dangerous - we'd be syncing incomplete data to the server. That's worse than a slow queue!

Actually, let's step back. How often will users really queue 100+ commits with huge messages? This feels like premature optimization. For MVP, let's:

1. Keep simple JSON format
2. Add warning if queue file > 50MB
3. Document: "Keep queue small by syncing regularly"
4. Defer compression to Phase 2 if users report issues

Sound good?

Now, different topic: Security. The queue file contains commit messages that might have sensitive data (API keys, passwords accidentally committed). File permissions are 0600 (owner only), but what about:
- Backups being created by Time Machine / system backup tools
- Queue files in shared home directories
- Users accidentally `git add ~/.commitkit/queues`

Should we warn about this in docs?

---

## Round 12

**👨‍💻 Developer:**
Good security thinking! Let's address:

**File permissions:** Already handled with 0600 (owner only)

**Backups (Time Machine, etc.):**
- Queue files will be backed up by default
- If queue contains sensitive data, user should sync/clear it regularly
- Document: "Queue files are local-only but may be included in system backups"

**Git tracking:**
- Add to `.gitignore_global`: `.commitkit/`
- Warn in installation docs: "Never commit your ~/.commitkit directory"

**Shared home directories:**
- In multi-user systems, ~/.commitkit is still user-owned (0700 directory)
- But we should document this risk
- Add check: if `HOME` is on NFS, warn user?

I think for MVP we can handle this with documentation + proper permissions. Add this section to design doc?

```markdown
## Security Considerations

- Queue files: 0600 permissions (user-readable only)
- Queue directory: 0700 permissions
- API keys: stored separately from queue
- Sensitive commits: sync/clear queue regularly
- System backups: may include queue files
- Never commit ~/.commitkit to git
```

**🔎 Reviewer:**
Yes, add that section! Though I'd strengthen it:

```markdown
## Security Considerations

### File Permissions
- Queue files: 0600 (user-readable only)
- Queue directory: 0700
- Lock files: 0600
- API config: 0600

### Sensitive Data
- ⚠️ Queue files may contain commit messages with sensitive data
- ⚠️ System backups (Time Machine, etc.) will include queues
- Best practice: Sync regularly to keep queue small
- If commit contains secrets: sync immediately (don't queue)

### Multi-User Systems
- On NFS/shared home directories: queue files may be visible to admins
- Consider: only use CommitKit on single-user systems or with encrypted home

### API Keys
- Stored separately in ~/.commitkit/config.yml
- Never stored in queue files
- If compromised: rotate via settings page
```

Now let's talk about the DLQ. You're moving commits to DLQ after 5 failures OR 14 days. But what if a user goes on vacation for 3 weeks? All their queued commits would move to DLQ even though there's nothing wrong with them. Should the 14-day threshold only apply to commits that have been attempted at least once?

---

## Round 13

**👨‍💻 Developer:**
Excellent point! Let's refine the DLQ rules:

**Current proposal:**
- Move to DLQ after 5 failed attempts OR 14 days

**Better proposal:**
- Move to DLQ after 5 failed attempts
- Move to DLQ after 14 days **IF** at least 1 sync attempt failed
- **Don't** move to DLQ if never attempted (user on vacation scenario)

This way:
- User on vacation: queue sits untouched (no DLQ move)
- User with persistent network issues: gets moved after 14 days of failures
- User with validation errors: gets moved after 5 attempts

Logic:
```ruby
def should_move_to_dlq?(commit)
  # Max attempts exceeded
  return true if commit.attempts >= 5

  # Stale AND has failed at least once
  age = Time.now - commit.queued_at
  return true if age > 14.days && commit.attempts > 0

  false
end
```

Better?

**🔎 Reviewer:**
Yes, much better! That fixes the vacation scenario.

But now I'm thinking about the user experience. Imagine:
- User works offline for a week (remote cabin, no internet)
- Makes 50 commits
- Returns, runs `commitkit queue sync`
- Network is still flaky, 3 commits fail
- User gives up, waits a day
- Runs `queue sync` again, those 3 fail again
- Now those 3 commits have 2 attempts

Two weeks later, those 3 commits auto-move to DLQ because they've been in queue for 14+ days with attempts > 0.

But the user might not even know! They committed successfully to git. Should we send an email notification when commits move to DLQ? Or at least show a prominent warning on next commit?

---

## Round 14

**👨‍💻 Developer:**
You're right that silent DLQ moves are problematic! Let's add visibility:

**When commits move to DLQ:**
```bash
$ commitkit queue sync
Syncing 50 queued commits...
✓ Synced 47 commits
✗ Failed 3 commits (moved to DLQ)
  - abc123: "Add feature X" (5 attempts failed)
  - def456: "Fix bug Y" (14+ days old, 2 attempts)

💡 Review with 'commitkit queue dlq list'
```

**On next commit (if DLQ non-empty):**
```bash
$ git commit -m "New feature"
[main xyz789] New feature
✓ Synced to CommitKit
⚠️  3 commits in dead letter queue need attention
💡 Run 'commitkit queue dlq list' to review
```

**Weekly digest (if enabled):**
Email: "You have 3 commits in DLQ that couldn't be synced"

For MVP, let's do the CLI warnings. Email notifications can be Phase 2. Sound good?

**🔎 Reviewer:**
CLI warnings are perfect for MVP! Email can wait.

Now let's talk about the `committed_at` timestamp. The CLI extracts this from `git log`. But what if:

1. User rebases commits (changes commit hashes AND timestamps)
2. User amends a commit (changes hash, keeps timestamp?)
3. Clock skew: user's system clock is wrong when committing

For case 1 (rebase): after rebase, commit hashes change. If we've already synced the old hash, now we'll sync the new hash as a "new" commit. User gets duplicates in dashboard. How do we handle this?

---

## Round 15

**👨‍💻 Developer:**
Ooh, this is tricky! Let's think through each case:

**1. Rebase (commit hash changes):**
```
Before: abc123 - "Add feature" (synced)
After:  def456 - "Add feature" (new hash after rebase)
```

We'd create a duplicate because hash changed. Possible solutions:

a) **Detect by message similarity** - fuzzy match on commit message
b) **Track by message hash** - add `message_hash` column, use as secondary deduplication
c) **Don't dedupe** - let duplicates happen, tell users "don't rebase synced commits"
d) **Add CLI flag** - `--force-resync-after-rebase` to delete old and resync

I lean toward (c) for MVP: document that rebase creates duplicates, tell users to rebase before syncing. Thoughts?

**2. Amend (hash changes, timestamp unclear):**
Same as rebase - hash changes, we can't detect it's the "same" commit.

**3. Clock skew:**
Commits get wrong `committed_at` timestamp, but that's user's problem (git also stores wrong time). We faithfully sync what git reports.

**🔎 Reviewer:**
I think (c) is too harsh on users. Rebasing is common in modern git workflows! Telling users "don't rebase after syncing" will frustrate power users.

What if we combine (b) and (d)?

- Add `message_hash` column (SHA256 of message)
- When syncing, check for duplicates by hash OR message_hash
- If message_hash matches but commit_hash differs: update the existing record

```ruby
existing = repository.commits.find_by(
  commit_hash: data[:commit_hash]
) || repository.commits.find_by(
  message_hash: Digest::SHA256.hexdigest(data[:message])
)

if existing
  # Update if hash changed (rebase case)
  existing.update!(commit_hash: data[:commit_hash])
  results[:skipped] << data[:commit_hash]
else
  # Create new
  repository.commits.create!(...)
end
```

This handles rebases gracefully. What do you think?

---

## Round 16

**👨‍💻 Developer:**
I like the intent, but I see problems:

**Problem 1: Multiple commits with same message**
```
Commit A: "Fix typo" - message_hash: abc123
Commit B: "Fix typo" - message_hash: abc123 (different file!)
```

Both have identical messages, different content. Using message_hash would wrongly treat them as duplicates.

**Problem 2: Amended messages**
```
Original: "Add feature" - synced with hash abc123
Amended:  "Add feature with tests" - new hash def456, new message
```

Message changed, so message_hash differs. We'd create a duplicate instead of updating.

**Alternative:** What if we add a config option:

```yaml
rebase_handling:
  mode: "warn"  # "warn", "dedupe", or "ignore"
```

- `warn` (default): Show warning if likely duplicate detected
- `dedupe`: Try to dedupe by message similarity (fuzzy)
- `ignore`: Just create duplicates

For MVP: use `warn`, show message like:
```
⚠️  Commit "Add feature" looks similar to existing abc123.
    Possible rebase detected. Use --force to sync anyway.
```

**🔎 Reviewer:**
Fair points about message_hash limitations. Your `warn` mode is safer.

But implementing "looks similar" detection requires fuzzy matching (Levenshtein distance, etc.). That's complex for MVP.

What if we simplify even more:

**For MVP:**
- No rebase detection
- Document: "Rebasing synced commits creates duplicates in dashboard"
- Add future enhancement: `commitkit sync --prune-duplicates` to clean up

**For Phase 2:**
- Implement proper deduplication
- Maybe use commit tree hash (content-based) instead of commit hash?

Let's not let perfect be the enemy of good. Ship something that works, iterate based on user feedback.

Agree?

---

## Round 17

**👨‍💻 Developer:**
You're absolutely right. I'm overthinking this for MVP. Let's go with:

**MVP:**
- No rebase detection
- Documentation: "Rebase before syncing to avoid duplicates"
- Error message if duplicate commit_hash detected: "Commit already exists"

**Phase 2:**
- Add `commitkit dedupe` command to find and merge duplicates
- Consider content-based deduplication

Done. Moving on!

New topic: The design doc mentions `commitkit queue sync --all` to sync all repositories. But how do we determine "all repositories"? Do we:
- Scan for all `*.json` files in `~/.commitkit/queues/`?
- Keep a registry file of known repositories?
- Walk common git directories (`~/src/`, `~/projects/`)?

What's the cleanest approach?

**🔎 Reviewer:**
Definitely scan the queues directory! Here's why:

**Option A: Scan `~/.commitkit/queues/`**
- ✅ Simple: just read directory
- ✅ Accurate: only repos with queued commits
- ✅ No registry to maintain
- ❌ Doesn't show repos with empty queues

**Option B: Registry file**
- ✅ Can track all repos (even without queues)
- ❌ Needs maintenance (add/remove)
- ❌ Can get out of sync

**Option C: Walk directories**
- ❌ Slow (scanning filesystem)
- ❌ Misses repos in unusual locations
- ❌ Privacy concern (scanning user's files)

Go with **Option A**. Implementation:

```ruby
def all_queues
  Dir.glob("#{queues_dir}/*.json").map do |file|
    repo_hash = File.basename(file, '.json')
    Queue.new(repo_hash)
  end
end
```

Simple and effective!

---

## Round 18

**👨‍💻 Developer:**
Agreed, Option A it is! Clean and simple.

Next question: Error handling for the batch endpoint. If the API returns a 500 error (server crashed, database down), what should the CLI do?

**Current behavior (I assume):**
```bash
$ commitkit queue sync
Error: Server error (500). Try again later.
```

Should we:
a) Leave commits in queue, user retries manually
b) Automatically retry with exponential backoff (1s, 2s, 4s...)
c) Move to DLQ after X retries
d) Ask user: "Retry now? (y/n)"

I'm leaning toward (a) for simplicity - just fail fast, stay in queue, user retries when ready.

**🔎 Reviewer:**
I agree with (a) for MVP! But let's distinguish between error types:

**Transient errors (retry likely to succeed):**
- 500 Internal Server Error
- 502 Bad Gateway
- 503 Service Unavailable
- Network timeout

**Permanent errors (retry won't help):**
- 401 Unauthorized (bad API key)
- 403 Forbidden
- 404 Not Found (wrong endpoint)
- 422 Validation errors (handled separately)

For transient errors, maybe we do a single retry after 1 second?

```ruby
def sync_with_retry
  sync_queue
rescue TransientError => e
  sleep 1
  sync_queue
rescue PermanentError => e
  raise "Cannot sync: #{e.message}. Fix the issue and try again."
end
```

This handles temporary blips without adding complexity. Thoughts?

---

## Round 19

**👨‍💻 Developer:**
One retry makes sense! But we should make it visible to the user:

```bash
$ commitkit queue sync
Syncing 10 queued commits...
✗ Server error (503). Retrying in 1 second...
✓ Synced 10 commits
```

And we should track whether this was a retry attempt in the queue metadata:

```ruby
commit.last_attempt_at = Time.now
commit.attempts += 1

if response.transient_error?
  sleep 1
  # Second attempt
  commit.attempts += 1
end
```

Wait, this means a single `sync` operation could increment attempts by 2 (initial + retry). Is that okay for the "5 attempts → DLQ" logic?

**🔎 Reviewer:**
Good catch! We should count a "sync operation" as 1 attempt, even if it does an internal retry:

```ruby
attempt_number = commit.attempts + 1

begin
  sync_commit(commit)
rescue TransientError
  sleep 1
  sync_commit(commit)  # Retry, but same attempt number
end

# Only increment once, after both tries complete/fail
commit.attempts = attempt_number
```

This way:
- User runs `sync` 5 times → 5 attempts → DLQ
- Each `sync` can internally retry once for transient errors
- Attempt count reflects "user actions" not "HTTP requests"

Make sense?

Alright, I think we're in good shape on most of the design! Let me check the implementation phases. You have Phase 1 (MVP) with these items:

- Queue storage structure
- Lockfile concurrency control
- `commitkit queue` commands
- Network error detection
- Batch sync endpoint
- Add `committed_at` and `synced_at` fields

Is this really shippable as an MVP? Let's talk estimates - how long would this take to build and test?

---

## Round 20

**👨‍💻 Developer:**
Let me break down the work:

**Backend (Rails API):**
- Migration for `committed_at`/`synced_at`: 30 min
- Update API to accept `sync_mode: append`: 2 hours
- Tests for batch endpoint: 2 hours
- **Subtotal: ~5 hours**

**CLI (Ruby gem):**
- Queue storage class (JSON read/write): 2 hours
- Lockfile wrapper: 1 hour
- Network error detection: 1 hour
- `queue sync` command: 3 hours
- `queue list/status/clear` commands: 2 hours
- Tests: 4 hours
- **Subtotal: ~13 hours**

**Documentation:**
- Update CLI docs: 1 hour
- Add queue troubleshooting guide: 1 hour
- **Subtotal: ~2 hours**

**Total: ~20 hours (2.5 days)**

For a single developer working full-time, this is maybe a week with buffer. Shippable? Yes, but tight.

Should we descope further?

**🔎 Reviewer:**
20 hours feels optimistic! Let's add some buffer for unknowns:

- Debugging weird edge cases: +4 hours
- Integration testing (manual): +3 hours
- Bug fixes from testing: +5 hours
- **Realistic total: ~32 hours (1 week)**

I think we can ship this, but let's defer the DLQ entirely. DLQ adds:
- New file format
- 5+ new commands
- More tests
- User education

That's easily another 10-15 hours. Let's ship MVP without DLQ, then add it in Phase 2 based on user feedback.

**Revised MVP:**
- ✅ Basic queue (no DLQ)
- ✅ `queue sync/list/status/clear`
- ✅ Network error detection
- ✅ Batch endpoint
- ❌ DLQ (Phase 2)
- ❌ Repository URL migration (Phase 2)

Agree?

---

## Round 21

**👨‍💻 Developer:**
Agreed! DLQ can wait. That brings us down to maybe 25-30 hours total - much more realistic.

One thing I want to revisit: the queue file location. We're using:
```
~/.commitkit/queues/<repo-hash>.json
```

Where `repo-hash` is... what exactly? MD5 of the repo URL? SHA256? First 8 chars?

I'm thinking:
```ruby
repo_hash = Digest::SHA256.hexdigest(repo_url)[0..15]  # 16 chars
```

This gives us:
- URL: `https://github.com/user/repo.git`
- Hash: `a1b2c3d4e5f6g7h8`
- File: `~/.commitkit/queues/a1b2c3d4e5f6g7h8.json`

16 chars should avoid collisions (256^16 possibilities). Thoughts?

**🔎 Reviewer:**
SHA256 truncated to 16 chars is fine for collision avoidance. But consider debuggability:

When a user runs `ls ~/.commitkit/queues/`, they see:
```
a1b2c3d4e5f6g7h8.json
9z8y7x6w5v4u3t2s.json
```

They have no idea which queue is which! What if we:

**Option 1: Use full SHA256 (64 chars)**
- No collisions, ever
- But filename is long

**Option 2: Include repo name in filename**
```
commitkit-a1b2c3d4.json
myproject-9z8y7x6w.json
```

**Option 3: Add a metadata file**
```
~/.commitkit/queues/
  a1b2c3d4e5f6g7h8.json
  a1b2c3d4e5f6g7h8.meta  # Contains: {"url": "https://..."}
```

I like Option 2 - easier to debug, still unique enough. What do you think?

---

## Round 22

**👨‍💻 Developer:**
Option 2 is clever! But risky - repo names can have special characters:

```
Repo: my-project/sub-module
Filename: my-project/sub-module-a1b2c3d4.json  ❌ (slash in filename!)

Repo: my project (spaces)
Filename: my project-a1b2c3d4.json  ❌ (spaces problematic)
```

We'd need to sanitize:

```ruby
def safe_filename(repo_url, hash)
  name = repo_url.split('/').last.gsub(/[^a-z0-9]/i, '-')
  "#{name}-#{hash}.json"
end

# "https://github.com/user/my-project.git"
# → "my-project-git-a1b2c3d4.json"
```

This works, but now we're parsing URLs and sanitizing strings - added complexity.

What if we stick with hash-only filenames, but add a `--verbose` flag to list commands?

```bash
$ commitkit queue list
3 commits queued (run with --verbose for repo details)

$ commitkit queue list --verbose
Repository: https://github.com/user/repo.git
Queue file: ~/.commitkit/queues/a1b2c3d4e5f6g7h8.json
3 commits queued
```

Simpler implementation, still debuggable when needed.

**🔎 Reviewer:**
Fair point about special characters. Your `--verbose` approach is cleaner.

Actually, wait - each queue file already contains the repository URL in its JSON:

```json
{
  "repository_url": "https://github.com/user/repo.git",
  "commits": [...]
}
```

So we can always read the file to see which repo it is. For debugging, user can just:

```bash
$ cat ~/.commitkit/queues/a1b2c3d4.json | grep repository_url
"repository_url": "https://github.com/user/repo.git"
```

Or we add a helper:

```bash
$ commitkit queue which-repo a1b2c3d4
https://github.com/user/repo.git
```

Let's just use the hash. Keep it simple.

---

## Round 23

**👨‍💻 Developer:**
Agreed, hash-only is simplest. Moving on!

Let's talk about testing strategy. The design doc lists unit tests and integration tests. For the queue system specifically, what test scenarios are critical?

**My list:**
1. Happy path: commit while offline → queue → sync online
2. Concurrent access: two terminals queueing simultaneously
3. Corrupted queue file → graceful error
4. Large queue (100+ commits) → performance acceptable
5. Network errors → commit added to queue
6. Partial sync failure → correct commits removed from queue
7. Lockfile timeout → helpful error message

Am I missing any critical scenarios?

**🔎 Reviewer:**
Good list! Add these:

8. **Queue empty:** Running `queue sync` with no queued commits shows "Nothing to sync"
9. **Duplicate commits:** Queueing same commit twice (same hash) → dedupe or error
10. **Clock skew:** Commits with `committed_at` in the future → still syncs correctly
11. **Permissions:** Queue file with wrong permissions (0644 instead of 0600) → warning or auto-fix
12. **Interrupted sync:** User Ctrl+C during sync → queue not corrupted
13. **API rate limiting:** Server returns 429 → commits stay in queue

Also, for testing concurrent access (#2), how will you test this? Forking processes in tests can be flaky. Maybe use threads + sleep to simulate timing issues?

---

## Round 24

**👨‍💻 Developer:**
Good additions! For concurrent access testing, I'm thinking:

```ruby
# spec/queue_spec.rb
it "handles concurrent writes" do
  threads = 10.times.map do |i|
    Thread.new do
      queue = Queue.new(repo_hash)
      queue.add(commit: "commit_#{i}")
    end
  end

  threads.each(&:join)

  queue = Queue.new(repo_hash)
  expect(queue.commits.size).to eq(10)
  expect(queue.commits.map(&:hash).uniq.size).to eq(10)  # No data loss
end
```

This tests thread-safety with `flock`. For process-level testing, we could use:

```ruby
it "handles concurrent processes" do
  10.times.map do |i|
    fork do
      queue = Queue.new(repo_hash)
      queue.add(commit: "commit_#{i}")
    end
  end.each { |pid| Process.wait(pid) }

  # Verify all 10 commits in queue
end
```

But forking in tests is indeed flaky. Maybe we save process-level testing for manual QA?

**🔎 Reviewer:**
Thread tests are good for CI. Process tests are better as manual/integration tests.

Here's another question: What happens if the queue file format changes in a future version? Say we add a new field or restructure the JSON. How do we handle migration?

Version the queue file format:

```json
{
  "version": 1,
  "repository_url": "...",
  "commits": [...]
}
```

Then in code:

```ruby
def load_queue
  data = JSON.parse(File.read(queue_file))

  case data["version"]
  when 1
    parse_v1(data)
  when 2
    parse_v2(data)
  else
    raise "Unsupported queue version: #{data['version']}"
  end
end
```

This gives us forward compatibility. Worth adding now, or defer?

---

## Round 25

**👨‍💻 Developer:**
Versioning is smart! Let's add it to MVP - it's just one extra line:

```ruby
def write_queue(commits)
  data = {
    version: 1,
    repository_url: repo_url,
    commits: commits
  }

  File.write(queue_file, JSON.pretty_generate(data))
end
```

And in `load_queue`, we can just check:

```ruby
def load_queue
  data = JSON.parse(File.read(queue_file))

  unless data["version"] == 1
    raise QueueVersionError, "Queue version #{data['version']} not supported. Please upgrade CommitKit."
  end

  data["commits"]
end
```

For MVP, we only support version 1. In future, we add migration logic. This is like 5 extra lines - worth it for future-proofing.

**🔎 Reviewer:**
Agreed! Small investment, big future payoff.

Alright, I think we've covered most of the major concerns! Let me summarize what we've changed:

**Design changes from review:**
1. ✅ Defer DLQ to Phase 2 (reduce MVP scope)
2. ✅ Migration: add columns as nullable, backfill, then add NOT NULL
3. ✅ API: reuse POST endpoint with `sync_mode` parameter
4. ✅ API response: include `synced_hashes` and `skipped_hashes` arrays
5. ✅ Error handling: individual transactions per commit
6. ✅ DLQ age threshold: only if attempts > 0 (vacation scenario)
7. ✅ Rebase handling: defer to Phase 2, document limitations
8. ✅ Queue file: hash-only filename for simplicity
9. ✅ Retry logic: single automatic retry for transient errors
10. ✅ Attempt counting: one attempt per sync operation (not per HTTP request)
11. ✅ Queue versioning: add `version: 1` field
12. ✅ Security: document backup/NFS risks

Anything else we should nail down before approving this design?

---

## Round 26

**👨‍💻 Developer:**
Great summary! A few more things to nail down:

**1. CLI output verbosity:**
Should we have `-v/--verbose` and `-q/--quiet` flags for sync operations?

```bash
$ commitkit queue sync          # Normal: show summary
$ commitkit queue sync -v       # Verbose: show each commit
$ commitkit queue sync -q       # Quiet: only errors
```

**2. Dry run:**
Should we support `--dry-run` to preview what would be synced?

```bash
$ commitkit queue sync --dry-run
Would sync 10 commits:
  - abc123: "Add feature"
  - def456: "Fix bug"
  ...
```

**3. Progress bar:**
For large queues (50+ commits), show progress?

```bash
$ commitkit queue sync
Syncing queued commits... [█████████░] 90% (45/50)
```

Which of these are worth including in MVP?

**🔎 Reviewer:**
Good questions!

**1. Verbosity flags:** YES for MVP
- `-v` is useful for debugging
- `-q` is useful for scripts/automation
- Easy to implement

**2. Dry run:** DEFER to Phase 2
- Useful, but not critical
- Adds test complexity
- Users can `queue list` to preview

**3. Progress bar:** DEFER to Phase 2
- Nice UX, but complex (need TTY detection, redrawing, etc.)
- For MVP, just show: "Syncing 50 commits..." then summary
- Can add fancy progress later

So: add verbosity flags, defer dry-run and progress bar.

One more thing - what about logging? Should queue operations be logged somewhere for debugging?

---

## Round 27

**👨‍💻 Developer:**
Logging is important! Let's add:

```
~/.commitkit/logs/queue.log
```

With structured entries:

```
[2025-11-03 10:30:05] INFO: Queued commit abc123 (network timeout)
[2025-11-03 10:35:10] INFO: Attempting sync of 10 commits
[2025-11-03 10:35:12] SUCCESS: Synced 10 commits
[2025-11-03 11:00:00] ERROR: Sync failed for def456 (validation error)
```

**Log rotation:**
- Keep last 7 days
- Max 10MB per file
- Rotate to `queue.log.1`, `queue.log.2`, etc.

**Configuration:**
```yaml
logging:
  level: info  # debug, info, warn, error
  max_size_mb: 10
  max_age_days: 7
```

This way users can debug issues without spamming stdout. Sound good?

**🔎 Reviewer:**
Yes! But keep it simple for MVP:

- Single log file (no rotation yet - defer to Phase 2)
- Basic log levels (info, error)
- Only log queue operations (not every CLI command)

Rotation and advanced config can come later.

```ruby
# Simple logger for MVP
class QueueLogger
  def initialize
    @log_file = File.join(CommitKit.home, "logs", "queue.log")
    FileUtils.mkdir_p(File.dirname(@log_file))
  end

  def info(message)
    log("INFO", message)
  end

  def error(message)
    log("ERROR", message)
  end

  private

  def log(level, message)
    File.open(@log_file, "a") do |f|
      f.puts "[#{Time.now.iso8601}] #{level}: #{message}"
    end
  end
end
```

~50 lines of code, very maintainable.

Actually, I just realized - we haven't discussed performance testing. With 100+ commits, is there a risk of:
- API timeout (request too large)
- Database deadlock (many inserts)
- Memory issues (loading large JSON)

Should we add performance benchmarks?

---

## Round 28

**👨‍💻 Developer:**
Performance testing is important! Let's think through the limits:

**API request size:**
- 100 commits × ~2KB avg = ~200KB request body
- Most servers handle up to 10MB easily
- We're safe until ~5,000 commits

**Database inserts:**
- We're doing individual inserts (not a huge transaction)
- PostgreSQL handles this fine
- Biggest risk: unique constraint checks on commit_hash (indexed, so fast)

**Memory:**
- Loading 100MB JSON file into memory: ~100MB RAM
- Ruby can handle this easily
- Becomes an issue at ~1GB+ (10,000+ commits)

**For MVP:**
- Document: "Queue tested up to 100 commits"
- Warn at 50 commits: "Consider syncing"
- Hard limit at 1,000 commits: "Queue too large, split into batches"

**For Phase 2:**
- Add performance benchmarks (RSpec benchmark-ips)
- Optimize if users report issues
- Maybe batch large queues into multiple API calls

Sound reasonable?

**🔎 Reviewer:**
Reasonable! Though I'd lower the hard limit to 500 instead of 1,000. Beyond that, something is probably wrong (user has been offline for months?).

Also, for the "queue too large" error, let's make it actionable:

```
⚠️ Queue too large: 502 commits.

Options:
  1. Sync in smaller batches: commitkit queue sync --limit 100
  2. Clear queue and resync: commitkit queue clear && commitkit sync --delete-all-and-resync
  3. Contact support if you need help

Which option? (1-3):
```

Wait, we don't have `--limit` flag yet. Should we add it?

```bash
# Sync first 100 commits only
$ commitkit queue sync --limit 100
```

---

## Round 29

**👨‍💻 Developer:**
The `--limit` flag is smart for large queues! Let's add it:

```ruby
def sync(limit: nil)
  commits_to_sync = queue.commits
  commits_to_sync = commits_to_sync.first(limit) if limit

  response = api.batch_sync(commits_to_sync)
  update_queue_based_on_response(response)

  if limit && queue.commits.size > 0
    puts "✓ Synced #{limit} commits. #{queue.commits.size} remaining in queue."
    puts "💡 Run 'commitkit queue sync' again to continue."
  end
end
```

This gives users control over large syncs. For MVP:
- Add `--limit` flag
- Document usage
- Test with large queues

Should be ~1 hour extra dev time. Worth it?

**🔎 Reviewer:**
YES, worth it! This is a safety valve for edge cases. 1 hour is a good investment.

Okay, I think we're in great shape now! Let's finalize:

**Approved for MVP:**
- ✅ Basic queue (no DLQ yet)
- ✅ Commands: sync, list, status, clear
- ✅ Flags: --limit, -v/--verbose, -q/--quiet
- ✅ Batch sync API endpoint
- ✅ Database migration (committed_at, synced_at)
- ✅ Lockfile concurrency
- ✅ Network error detection
- ✅ Single automatic retry for transient errors
- ✅ Basic logging
- ✅ Queue file versioning
- ✅ Warnings at 50+ commits

**Deferred to Phase 2:**
- Dead letter queue
- Repository URL migration detection
- Dry run mode
- Progress bars
- Log rotation
- Advanced deduplication (rebase handling)

**Estimated effort:** 30-35 hours (1 week)

Do we have consensus? Should I update the design doc with all our discussed changes?

---

## Round 30

**👨‍💻 Developer:**
Consensus achieved! Let me update the design doc with all the refinements:

**Key changes to document:**
1. DLQ deferred to Phase 2 (mentioned but marked as phase 2)
2. API endpoint: reuse POST with `sync_mode` parameter
3. Response format: include hash arrays
4. Migration: nullable → backfill → NOT NULL
5. Error handling: individual transactions
6. Retry logic: single automatic retry
7. Attempt counting: per user action
8. Queue filename: hash-only
9. Add verbosity flags (-v, -q)
10. Add --limit flag for large queues
11. Add basic logging (no rotation yet)
12. Add queue versioning
13. Security documentation
14. Performance limits (warn at 50, limit at 500)
15. Test scenarios expanded

I'll update the doc and mark it as **"Approved - Ready for Implementation"**.

**🔎 Reviewer:**
Perfect! This has been a thorough review. The design is solid, scope is reasonable for MVP, and we have a clear path forward.

**Final approval:** ✅ APPROVED

Go forth and build! And remember:
- Write tests first (TDD)
- Keep it simple
- Ship early, iterate based on user feedback
- Document as you go

Looking forward to seeing this feature in production!

---

**End of Review - Consensus Reached** 🎉

**Outcome:** After this comprehensive review, the feature was deemed too complex for current priorities and has been shelved. The discussion above captures valuable design decisions, edge cases, and implementation considerations for when the team is ready to revisit offline queue support in the future.
