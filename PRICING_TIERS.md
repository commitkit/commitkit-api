# CommitKit Pricing Tiers & Feature Ideas

## Pricing Model Considerations

### Option 1: Commits Per Month Tiering
```
Free Tier:     100 commits/month
Pro Tier:      1,000 commits/month ($9/month)
Premium Tier:  10,000 commits/month ($29/month)
Enterprise:    Unlimited commits (custom pricing)
```

**Pros:**
- Aligns with actual usage/value
- Easy to meter and enforce
- Scales with user activity
- Heavy users pay more (fair)

**Cons:**
- Need to track and limit commits
- Could discourage frequent committing (bad developer behavior)
- Monthly limits can be confusing

### Option 2: Feature-Based Tiering
```
Free Tier:     Personal use only, basic tracking
Pro Tier:      Advanced features (LLM analysis, exports, etc.)
Team Tier:     Multi-user features
Enterprise:    Team management, SSO, etc.
```

**Recommendation:** Hybrid approach - Feature-based tiers with commit volume limits as a secondary constraint.

---

## Feature Tier Mapping

### Free Tier (Individual Developer)
- ✅ Automatic commit tracking via git hook
- ✅ Basic dashboard to view commits
- ✅ Manual sync for historical commits
- ✅ Up to 100 commits/month
- ✅ Single user only (tracks their own commits)
- ❌ No LLM analysis
- ❌ No resume generation
- ❌ No team features

### Pro Tier ($9-15/month)
- ✅ Everything in Free
- ✅ Up to 1,000 commits/month
- ✅ LLM-powered commit analysis (BYOK)
- ✅ Resume bullet generation
- ✅ Advanced filtering and search
- ✅ Export to PDF/JSON
- ✅ Performance review assistance
- ❌ No team features

### Team/Premium Tier ($29-49/month per team lead)
- ✅ Everything in Pro
- ✅ Up to 10,000 commits/month (team total)
- ✅ **`--all-authors` flag** - Sync team members' commits
- ✅ Team dashboard (view team's work)
- ✅ Team analytics and insights
- ✅ Multiple repository support
- ✅ Team performance reports
- ❌ No SSO, no advanced admin features

### Enterprise Tier (Custom Pricing)
- ✅ Everything in Team
- ✅ Unlimited commits
- ✅ SSO/SAML authentication
- ✅ Advanced admin controls
- ✅ Custom integrations
- ✅ Dedicated support
- ✅ SLA guarantees
- ✅ On-premise deployment option

---

## Feature Flag: `--all-authors`

### Use Case
Team leads or engineering managers want to track their entire team's commits:
```bash
# Team lead syncing their team's repository
commitkit sync --all-authors
```

This would sync commits by ALL authors in the repo, not just the current user.

### Requirements for `--all-authors`
1. **Tier Restriction:** Team or Enterprise tier only
2. **Permission Check:** User must have "team lead" or "manager" role
3. **API Validation:** Backend checks if user's plan allows multi-author syncing
4. **Billing Impact:** Team commits count toward team's monthly limit

### Implementation Notes
```javascript
// CLI checks user's plan before allowing --all-authors
if (flags.allAuthors && userPlan !== 'team' && userPlan !== 'enterprise') {
  console.error('❌ --all-authors requires Team or Enterprise plan');
  console.error('   Upgrade at: https://commitkit.dev/pricing');
  process.exit(1);
}
```

### API Endpoint
```
POST /api/v1/commits/batch
Headers:
  Authorization: Bearer <token>
  X-Sync-Mode: all-authors (requires team/enterprise plan)
```

Backend validates:
- User has active Team/Enterprise subscription
- Team hasn't exceeded monthly commit limit
- User has permission to sync others' commits

---

## Commit Volume Limits - Implementation

### How to Enforce
1. **Track commits per user per month** in `commit_usage` table
2. **Check limit before accepting new commits** (both hook and sync)
3. **Soft limit:** Warn user at 80% usage
4. **Hard limit:** Return 429 (Too Many Requests) at 100%

### Database Schema
```sql
CREATE TABLE commit_usage (
  user_id INTEGER,
  month DATE,  -- e.g., '2024-11-01'
  commit_count INTEGER DEFAULT 0,
  plan_limit INTEGER,  -- 100, 1000, 10000, or NULL (unlimited)
  PRIMARY KEY (user_id, month)
);
```

### API Response When Limit Exceeded
```json
{
  "error": "Monthly commit limit exceeded",
  "current_usage": 105,
  "plan_limit": 100,
  "upgrade_url": "https://commitkit.dev/pricing"
}
```

CLI shows:
```
❌ Monthly commit limit exceeded (105/100)
   Upgrade to Pro for 1,000 commits/month: https://commitkit.dev/pricing
```

---

## Pricing Strategy Notes

### Why Commit-Based Limits?
- **Aligns with value:** More commits = more value from the tool
- **Prevents abuse:** Free tier can't be used for large teams
- **Upsell path:** Natural upgrade path as users commit more
- **Metering is easy:** Every API call is already tracked

### Why NOT Only Commit-Based?
- **Could discourage good habits:** Users might avoid committing to save quota
- **Hard to predict:** Developers don't know how much they'll commit
- **Competitor risk:** If competitors offer unlimited, we look worse

### Recommended Hybrid Approach
- **Primary differentiator:** Features (LLM analysis, team features, etc.)
- **Secondary constraint:** Commit volume limits (generous, not restrictive)
- **Enterprise:** Unlimited commits, custom features

### Example Messaging
"CommitKit Pro: $12/month - Includes LLM-powered analysis, resume generation, and up to 1,000 commits/month (most developers commit 200-400/month)"

---

## Future Considerations

### Team Features (Beyond `--all-authors`)
- Team dashboard showing all team members' activity
- Aggregate team statistics
- Team performance trends
- Cross-repository tracking
- Manager reports: "What did my team ship this sprint?"

### Analytics Features (Premium/Enterprise)
- Commit frequency trends
- Code churn analysis
- Team velocity metrics
- Engineering productivity insights
- Integration with project management tools (Jira, Linear, etc.)

### Integration Features (Enterprise)
- Slack notifications for team commits
- Weekly digest emails
- Integration with performance review systems
- API access for custom integrations
- Webhooks for commit events

---

## Next Steps for MVP

**For MVP, we'll:**
1. ✅ Build `commitkit sync` without `--all-authors` flag
2. ✅ No commit limits yet (everyone gets unlimited)
3. ✅ Focus on individual developer use case
4. ⏳ Add usage tracking in backend (count commits per user)
5. ⏳ Add plan/tier to User model (default: 'free')

**Post-MVP:**
1. Implement commit volume limits
2. Build pricing/subscription page
3. Add `--all-authors` flag with tier gating
4. Build team dashboard
5. Integrate payment processing (Stripe)

---

## Questions to Answer Later

1. **How to handle team billing?**
   - Per seat pricing? ($12/user/month)
   - Per team pricing? ($49/month for 5 users)
   - Hybrid? (Base price + per seat)

2. **Free tier for open source?**
   - Unlimited commits for public repos?
   - Requires GitHub verification?

3. **Student discounts?**
   - 50% off Pro tier for students?
   - Verify via GitHub Student Pack?

4. **Annual discounts?**
   - 2 months free if paid annually?
   - $99/year vs $12/month?

---

**Last Updated:** 2024-11-03
