# Commit History Tracking Analysis

## Question

Should CommitKit maintain a local history file tracking synced commits, then periodically check for divergence between our tracked history and the user's actual git log?

## Proposed Approach

Maintain `~/.commitkit/history/<repo-hash>.json`:

```json
{
  "repository_url": "https://github.com/user/repo.git",
  "last_sync_at": "2025-11-03T15:30:00Z",
  "commits_synced": [
    {
      "commit_hash": "abc123",
      "synced_at": "2025-11-03T10:00:00Z",
      "parent_hash": "def456"
    }
  ]
}
```

Then periodically check for divergence:
```
Our history: abc123 → def456 → ghi789
Git log now: abc123 → xyz999 → ghi789

Divergence detected at def456 (was rebased/removed)
```

---

## Advantages

### 1. Detect Rebases/Force Pushes

When users rebase, amend, or force-push:
```bash
$ commitkit sync

⚠️  Detected divergence at commit def456 (rebased away)
    3 commits need resyncing:
      - xyz999 (new after rebase)
      - modified-ghi789 (amended)
      - jkl012 (new)

Sync these 3 commits? (y/N)
```

**Benefit:** Smart resync instead of blind full resync

### 2. Audit Trail

Know exactly what was synced and when:
```bash
$ commitkit history

Repository: https://github.com/user/repo.git
Last sync: 2 hours ago (50 commits)
Total synced: 1,247 commits
First sync: October 15, 2025

Recent syncs:
  - 50 commits on Nov 3 at 2:30pm
  - 23 commits on Nov 2 at 4:15pm
  - 15 commits on Nov 1 at 9:00am
```

**Benefit:** Debugging and transparency

### 3. Avoid Duplicate Syncs

If server loses data or user resyncs, we know exactly what to resend:
```bash
$ commitkit resync --verify

Checking server against local history...
✓ 1,200 commits match
✗ 47 commits missing from server
  → Resyncing 47 missing commits
```

**Benefit:** Efficient recovery from server data loss

### 4. Smart Sync Status

Show users what's pending:
```bash
$ git status
On branch main
Your branch is ahead of 'origin/main' by 3 commits.

$ commitkit status
CommitKit status:
  ✓ 1,247 commits synced
  ⏳ 3 commits pending sync
  Last sync: 2 hours ago
```

**Benefit:** Clear visibility into sync state

---

## Disadvantages

### 1. Complexity

**New code needed:**
- History file read/write (~50 lines)
- Lockfile management (~30 lines)
- Divergence detection (~100 lines)
- Git log parsing for comparison (~50 lines)
- File corruption handling (~50 lines)
- **Total: ~280 lines of new code**

**New failure modes:**
- History file corrupted
- Concurrent access from multiple terminals
- File permissions issues
- Disk full when writing history
- Lock acquisition failures

### 2. Divergence is Normal in Git

Common workflows that cause "divergence":

**Interactive Rebase:**
```bash
git rebase -i HEAD~5
# User squashes 3 commits into 1
# Old: a → b → c → d → e
# New: a → bcd → e

CommitKit sees: "b, c, d disappeared! Divergence!"
User sees: "I cleaned up my history (expected)"
```

**Amending:**
```bash
git commit --amend
# Old hash: abc123
# New hash: def456 (same changes, different hash)

CommitKit sees: "abc123 disappeared! Divergence!"
User sees: "I fixed my commit message (expected)"
```

**Cherry-picking:**
```bash
git cherry-pick other-branch
# Creates new commit with same changes but different hash

CommitKit sees: "Similar commit! Divergence?"
User sees: "I applied a fix from another branch (expected)"
```

**Result:** Most "divergences" are intentional user actions. Warnings become noise.

### 3. Server is Already Source of Truth

We already have the commit hash on server as unique identifier:

**Current behavior (no history file):**
```
User rebases:
  Old: abc123 - "Add feature"
  New: def456 - "Add feature" (rebased)

Server state:
  - Commit abc123 exists (original)
  - Commit def456 gets synced (rebased version)

Dashboard shows both commits (correct - they ARE different)
```

**This is actually correct behavior:**
- Different commit hashes = different commits
- Even if message is identical
- Git considers them distinct

**With history file:**
```
User rebases:
  History file says: "We synced abc123"
  Git log says: "abc123 doesn't exist, only def456"

Warning: "Divergence detected! abc123 missing!"
Action: ???
```

What should we do?
- Delete abc123 from server? (Loss of history)
- Keep both? (Same as current behavior)
- Ask user every time? (Annoying)

**Conclusion:** History file doesn't help us make better decisions.

### 4. False Positives

**Switching branches:**
```bash
# On main branch, sync 50 commits
git checkout feature-branch
# Now git log shows different commits

CommitKit: "Divergence! 50 commits missing!"
User: "I just switched branches..."
```

**Multiple clones:**
```bash
# Desktop: sync 100 commits
# Laptop: clone repo, only has 80 commits locally

CommitKit on laptop: "Divergence! 20 commits missing!"
User: "Those are on my other machine..."
```

**Collaborators force-pushing:**
```bash
# Teammate force-pushes to shared branch
# Your local history doesn't match remote

CommitKit: "Divergence detected!"
User: "My teammate rewrote history (expected in our workflow)"
```

**Result:** Too many false alarms, users will ignore warnings.

### 5. File Management Overhead

**Local state to manage:**
- History files for each repo
- Backup files (corruption recovery)
- Lock files (concurrent access)
- Cleanup old history (disk space)

**Edge cases:**
- User deletes history file manually
- Disk full during write
- Power loss during update
- NFS/network drive latency
- Multiple devices syncing same repo

**Each edge case needs:**
- Detection code
- Recovery code
- User-facing error messages
- Tests

---

## Decision: ❌ Don't Implement History File

### Reasoning

1. **Server already has commit hashes (our history)**
   - No need to duplicate locally
   - Server is authoritative source of truth
   - Simpler architecture

2. **Divergence is usually intentional**
   - Rebasing is a feature, not a bug
   - Users expect commits to "change"
   - Warnings would be mostly noise

3. **Better handled at dashboard level**
   - Show duplicate commits gracefully
   - Badge "rebased version" on similar commits
   - Option to hide/merge duplicates
   - Solves UX problem without CLI complexity

4. **Complexity not justified**
   - 280+ lines of code
   - Multiple new failure modes
   - Maintenance burden
   - Edge cases to handle

5. **Simple is better**
   - Current approach works
   - Commit hash uniqueness is sufficient
   - Server-side deduplication easier to debug

---

## Alternative: Server-Side Sync Tracking

Instead of local history file, track syncs on server:

### Database Schema

```ruby
class CreateSyncEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_events do |t|
      t.references :commit, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :synced_at, null: false
      t.string :source  # "cli", "manual", "resync", "bulk"
      t.string :cli_version
      t.string :device_id  # Optional: track which device

      t.timestamps
    end

    add_index :sync_events, [:commit_id, :synced_at]
    add_index :sync_events, [:user_id, :synced_at]
  end
end
```

### Usage

```ruby
# app/models/commit.rb
class Commit < ApplicationRecord
  has_many :sync_events

  def first_synced_at
    sync_events.minimum(:synced_at)
  end

  def sync_count
    sync_events.count
  end

  def last_synced_at
    sync_events.maximum(:synced_at)
  end

  def synced_from_devices
    sync_events.pluck(:device_id).compact.uniq
  end
end

# When syncing
commit.sync_events.create!(
  user: current_user,
  synced_at: Time.current,
  source: "cli",
  cli_version: CommitKit::VERSION,
  device_id: machine_id
)
```

### Benefits

**1. Single source of truth**
- Server-side only
- No local file management
- No synchronization between devices

**2. Rich analytics**
```sql
-- Commits synced in last week
SELECT * FROM commits
INNER JOIN sync_events ON commits.id = sync_events.commit_id
WHERE sync_events.synced_at > NOW() - INTERVAL '7 days';

-- Commits synced multiple times (rebase candidates)
SELECT commit_id, COUNT(*) as sync_count
FROM sync_events
GROUP BY commit_id
HAVING COUNT(*) > 1
ORDER BY sync_count DESC;

-- Most active sync hours
SELECT EXTRACT(HOUR FROM synced_at) as hour, COUNT(*)
FROM sync_events
GROUP BY hour
ORDER BY hour;
```

**3. Debugging**
```ruby
# Support request: "My commit never synced"
commit = Commit.find_by(commit_hash: "abc123")

if commit
  puts "Commit exists. Sync history:"
  commit.sync_events.each do |event|
    puts "- #{event.synced_at}: #{event.source} (#{event.cli_version})"
  end
else
  puts "Commit not found. Never synced."
end
```

**4. User dashboard features**
```erb
<!-- Dashboard -->
<div class="commit-stats">
  <p>First synced: <%= commit.first_synced_at.strftime("%b %d, %Y") %></p>
  <% if commit.sync_count > 1 %>
    <p class="text-muted">
      Synced <%= pluralize(commit.sync_count, 'time') %>
      <% if commit.synced_from_devices.many? %>
        from <%= pluralize(commit.synced_from_devices.size, 'device') %>
      <% end %>
    </p>
  <% end %>
</div>
```

**5. Duplicate detection**
```ruby
# Find commits with same message synced multiple times
def find_potential_duplicates
  Commit.joins(:sync_events)
        .select("commits.*, COUNT(sync_events.id) as sync_count")
        .group("commits.id")
        .having("COUNT(sync_events.id) > 1")
        .where("commits.message SIMILAR TO ?", "%")
end
```

### Drawbacks

**1. Database growth**
- One row per commit per sync
- If users resync often: N × sync_count rows
- Mitigation: Cleanup old sync_events (keep last 90 days)

**2. API overhead**
- Extra INSERT on every sync
- Mitigation: Minimal (one extra row)

**3. Privacy**
- Tracks user sync behavior
- Mitigation: Anonymous device_id, document in privacy policy

---

## Recommendation

### ✅ Implement Server-Side Sync Tracking

**Phase 1: Basic tracking**
- Add `sync_events` table
- Record sync timestamp on every commit sync
- Display "First synced" on dashboard

**Phase 2: Analytics**
- Sync count per commit
- Device tracking (optional)
- Duplicate detection queries

**Phase 3: Features**
- Dashboard: "Show only latest version" for rebased commits
- Badge: "Rebased" or "Amended" on similar commits
- Admin: Analytics dashboard for sync patterns

### ❌ Skip Local History File

**Reasons:**
- Server-side tracking is sufficient
- Avoids complexity and failure modes
- Better user experience (no warnings/noise)
- Easier to debug and maintain

---

## Related Decisions

### Handling Rebased Commits on Dashboard

Instead of preventing duplicates, handle them gracefully:

```erb
<!-- Dashboard UI for duplicate commits -->
<div class="commit-card">
  <div class="commit-header">
    <h3>Add payment processing</h3>
    <span class="badge badge-rebased">Rebased</span>
  </div>

  <p class="text-muted">
    This commit was rebased.
    <a href="#" data-toggle="collapse" data-target="#older-versions">
      Show 2 older versions
    </a>
  </p>

  <div id="older-versions" class="collapse">
    <ul class="list-unstyled">
      <li>
        <code>abc123</code> - Original (Nov 2, 2025)
        <a href="#">View</a>
      </li>
      <li>
        <code>def456</code> - Amended (Nov 3, 2025)
        <a href="#">View</a>
      </li>
    </ul>
  </div>
</div>
```

**Detection logic:**
```ruby
# app/models/commit.rb
def possible_versions
  # Find commits with same message but different hash
  Commit.where(
    user_id: user_id,
    repository_id: repository_id,
    message: message
  ).where.not(id: id)
      .order(committed_at: :desc)
end

def is_latest_version?
  possible_versions.where("committed_at > ?", committed_at).none?
end
```

---

## Conclusion

**Don't build local history file.**

**Instead:**
1. Add `sync_events` table for server-side tracking
2. Use for analytics and debugging
3. Handle duplicates gracefully on dashboard
4. Keep CLI simple (no history management)

This approach:
- ✅ Provides audit trail (server-side)
- ✅ Enables duplicate detection (dashboard)
- ✅ Simplifies CLI (no file management)
- ✅ Single source of truth (server)
- ✅ Better analytics (queryable database)

---

**Document Version:** 1.0
**Last Updated:** 2025-11-03
**Authors:** Richie Thomas, Claude (Anthropic)
**Status:** Decision - Do Not Implement Local History File
