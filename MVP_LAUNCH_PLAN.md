# CommitKit MVP Launch Plan

## Launch Date: TBD (After Week 4 of CLI Development + Testing)

---

## Executive Summary

**Goal:** Get 1000+ signups in first week, establish CommitKit as a must-have tool for developers updating their resumes.

**Core Channels:**
1. Product Hunt (Primary)
2. Hacker News (Primary)
3. Reddit (Secondary)
4. Email/Direct Outreach (Secondary)
5. Twitter (Optional - can skip)

**Timeline:** 4 weeks pre-launch → Launch day → 4 weeks post-launch

---

## Phase 1: Pre-Launch (Weeks -4 to -1)

### Week -4: Foundation

**Landing Page Polish**
- [ ] Clear hero section: "Never forget what you worked on - your git commits become resume bullets"
- [ ] 30-second demo video showing: install → commit → see summary in dashboard
- [ ] 3-5 feature highlights with screenshots
- [ ] Social proof section (ready for testimonials)
- [ ] Prominent CTA: "Install CLI" button
- [ ] Waitlist email signup form
- [ ] FAQ section addressing common concerns

**Beta Testing Recruitment**
- [ ] Reach out to 10-15 developer friends/colleagues
- [ ] Post in developer communities (ask for beta testers):
  - Dev.to
  - Indie Hackers
  - Reddit r/webdev (careful with self-promotion rules)
  - Relevant Discord servers
- [ ] Offer "Founding Member" perks:
  - Lifetime free tier
  - Priority support
  - Listed as founding member on site
  - Early access to new features

**Technical Preparation**
- [ ] Ensure production is stable
- [ ] Set up error monitoring (Sentry, Rollbar, or similar)
- [ ] Create demo account with sample data
- [ ] Prepare for traffic spike (check Render limits, consider scaling plan)
- [ ] Test installation on fresh machines (Mac, Linux, Windows)

### Week -3: Content Creation

**Product Hunt Assets**
- [ ] Product icon (512x512px, professional looking)
  - Consider Fiverr designer ($30-50)
  - Or use Midjourney/DALL-E for AI-generated icon
- [ ] Gallery images (1270x760px):
  1. Dashboard showing commits
  2. CLI installation process
  3. Git hook in action
  4. Resume bullet generation
  5. LLM analysis results
- [ ] Tagline (160 chars): "Turn your git commits into professional resume bullets automatically"
- [ ] Description (draft):
  ```
  CommitKit tracks your git commits and uses AI to generate professional
  resume bullet points. Never forget what you worked on again.

  Perfect for developers who:
  - Struggle to remember accomplishments during performance reviews
  - Update their resume once a year and forget everything
  - Want data-driven career documentation

  How it works:
  1. Install CLI: npm install -g commitkit
  2. Configure in your repos: commitkit init
  3. Make commits as normal - they're automatically tracked
  4. View AI-generated summaries in your dashboard
  5. Export as resume bullets when needed
  ```
- [ ] First comment (maker introduction):
  ```
  Hey Product Hunt! 👋

  I built CommitKit because I'm terrible at updating my resume. I'd work
  on cool projects all year, then when it came time to update my resume,
  I'd completely blank on what I actually accomplished.

  Your git commits are a perfect record of your work - but raw commit
  messages aren't resume-ready. CommitKit bridges that gap.

  Technical highlights:
  - Non-blocking git hooks (never slows down commits)
  - Background LLM analysis (bring your own OpenAI/Anthropic key)
  - Cross-platform CLI (works on Mac, Linux, Windows)
  - Privacy-first (your commits, your data)

  I'd love your feedback! What features would make this indispensable
  for you?
  ```

**Hacker News Post**
- [ ] Title (max 80 chars): "Show HN: CommitKit - Turn git commits into resume bullets with AI"
- [ ] Post draft:
  ```
  Hi HN,

  I built CommitKit to solve a personal problem: I'm terrible at remembering
  what I worked on when updating my resume.

  The tool:
  - CLI that hooks into your git repos
  - Tracks commits automatically (via post-commit hook)
  - Uses AI (your own OpenAI/Anthropic key) to generate summaries
  - Gives you resume-ready bullet points

  Technical details I'm proud of:
  - Background worker ensures git commits are never blocked
  - Hook chaining preserves your existing git hooks
  - JSONL queue for atomic job processing
  - MCP server for IDE integration (Claude Code, Cursor, etc.)

  Try it: npm install -g commitkit

  I'd love technical feedback - particularly around:
  - Git hook edge cases I might have missed
  - Performance optimization ideas
  - Privacy/security concerns

  Code is here: [GitHub link]
  Demo: [Video link]
  ```

**Demo Video** (Critical!)
- [ ] Script outline:
  1. Problem statement (15 seconds): "How many commits did you make last month? What were they?"
  2. Solution (15 seconds): "CommitKit tracks them automatically"
  3. Installation (20 seconds): Show `npm install -g commitkit` and `commitkit init`
  4. In action (30 seconds): Make commit, show it appears in dashboard with AI summary
  5. Export (20 seconds): Show resume bullet generation
  6. CTA (10 seconds): "Try it free: commitkit.dev"
- [ ] Record with Loom or ScreenFlow
- [ ] Keep it under 2 minutes (90 seconds ideal)
- [ ] Add subtitles (many watch on mute)
- [ ] Upload to YouTube + host on site

**Blog Post / Long-Form Content**
- [ ] Write launch post (options):
  - Option A: "Why I built CommitKit"
  - Option B: "The technical challenges of building a git commit tracker"
  - Option C: "Building in public: 4 weeks to MVP"
- [ ] Publish on:
  - Dev.to
  - Your blog (if you have one)
  - Medium (republish after a week)
- [ ] Include:
  - Personal story (why this matters)
  - Technical architecture diagram
  - Challenges faced and solved
  - Call to action (try it, give feedback)

### Week -2: Community Seeding

**Reddit Posts** (Careful with self-promotion rules!)
- [ ] r/cscareerquestions: "How do you keep track of accomplishments for performance reviews?"
  - Share CommitKit in comments if thread gains traction
  - Don't lead with product link
- [ ] r/webdev: Post in "Showoff Saturday" thread
- [ ] r/devtools: Share with technical focus
- [ ] r/SideProject: Full post allowed here

**Developer Communities**
- [ ] Indie Hackers: Share as "work in progress"
- [ ] Dev.to: Share as beta testing opportunity
- [ ] Hacker News "Ask HN": "How do you remember what you worked on for resume updates?"
  - Gauge interest, get feedback
  - Don't spam product link

**Email Waitlist Nurture**
- [ ] Send teaser email: "CommitKit launching next week"
- [ ] Include exclusive early access link
- [ ] Ask for feedback on beta

### Week -1: Final Prep

**Launch Day Checklist**
- [ ] Product Hunt hunter identified (or self-post as maker)
- [ ] All assets uploaded and ready
- [ ] Demo video finalized
- [ ] Landing page live and tested
- [ ] Production environment stress-tested
- [ ] Monitoring/alerting configured
- [ ] Social media posts scheduled (if using Twitter)
- [ ] Email draft ready for waitlist
- [ ] Response templates prepared for common questions

**Team/Support Prep** (if applicable)
- [ ] Block calendar for launch day (be available all day)
- [ ] Prepare FAQ for common questions
- [ ] Set up alerts for Product Hunt comments (respond within 30 min)
- [ ] Set up alerts for Hacker News replies

**Testimonial Collection**
- [ ] Get 3-5 testimonials from beta testers
- [ ] Add to landing page
- [ ] Use in Product Hunt description
- [ ] Format: "CommitKit saved me hours when updating my resume" - Name, Title

---

## Phase 2: Launch Day (The Big Day!)

### Timeline (All times Pacific)

**6:00 AM - Final Checks**
- [ ] Verify production is healthy
- [ ] Check all links work
- [ ] Test demo account works
- [ ] Verify monitoring is active

**9:00 AM - Product Hunt Launch**
- [ ] Post to Product Hunt (optimal time for visibility)
- [ ] Post maker comment immediately
- [ ] Pin on Twitter (if using)
- [ ] Share in Slack/Discord communities

**9:00 AM - 6:00 PM - Product Hunt Engagement**
- [ ] Respond to EVERY comment within 30 minutes
- [ ] Thank people for upvotes
- [ ] Engage thoughtfully with criticism
- [ ] Answer technical questions in detail
- [ ] Update top comment with popular Q&A

**10:00 AM - Hacker News Post**
- [ ] Post "Show HN" article
- [ ] Monitor for comments
- [ ] Respond within 15 minutes to early comments
- [ ] Be prepared for technical scrutiny
- [ ] Stay humble, acknowledge limitations

**10:30 AM - Reddit Posts**
- [ ] r/SideProject: Full launch post
- [ ] r/devtools: Technical focus post
- [ ] Other relevant subreddits (check rules first)

**11:00 AM - Email Launch**
- [ ] Send to waitlist: "CommitKit is live!"
- [ ] Include direct install link
- [ ] Personal note thanking them for interest
- [ ] Exclusive launch day perk (if applicable)

**12:00 PM - Dev.to Post**
- [ ] Publish launch blog post
- [ ] Share in relevant Dev.to tags

**Throughout Day**
- [ ] Monitor server health
- [ ] Watch for bug reports
- [ ] Respond to all feedback channels
- [ ] Share milestones: "50 signups!", "Product Hunt #3!", etc.

**End of Day**
- [ ] Thank everyone who supported
- [ ] Share final stats
- [ ] Identify any critical issues for next day

---

## Phase 3: Post-Launch (Weeks 1-4)

### Week 1: Momentum

**Immediate Follow-Up**
- [ ] Fix any critical bugs within 24 hours
- [ ] Respond to all support requests
- [ ] Thank top supporters on Product Hunt/HN
- [ ] Post "Launch Results" update:
  - Stats (signups, commits tracked, etc.)
  - Top feedback themes
  - What's next
  - Thank you to community

**Content**
- [ ] Write "Launch Day Retrospective" blog post
- [ ] Share lessons learned
- [ ] Technical deep dive: "How CommitKit's background worker works"

**Community**
- [ ] Continue engaging on Product Hunt (comments come for days)
- [ ] Follow up with Hacker News discussion
- [ ] Respond to Reddit comments

### Week 2-3: Growth

**User Stories**
- [ ] Interview 3-5 users about their experience
- [ ] Create case studies
- [ ] Video testimonials (if users willing)
- [ ] Share on social media

**Technical Content**
- [ ] Write deep-dive blog posts:
  - "Building a non-blocking git hook"
  - "MCP integration with Claude Code"
  - "Why we chose BYOK over managing API keys"
- [ ] Post to Dev.to, Hacker News

**Outreach**
- [ ] Reach out to developer influencers/YouTubers
- [ ] Offer free tool review
- [ ] Ask for honest feedback

**Iteration**
- [ ] Implement top 3 requested features
- [ ] Fix top 5 reported bugs
- [ ] Announce updates

### Week 4: Long Game

**SEO/Content**
- [ ] Write comparison posts:
  - "CommitKit vs manually tracking work"
  - "Git commit history vs traditional time tracking"
- [ ] Optimize landing page for keywords
- [ ] Build backlinks

**Partnerships**
- [ ] Reach out to resume building tools
- [ ] Reach out to career coaching services
- [ ] Explore integration opportunities

**Analytics Review**
- [ ] Analyze signup funnel
- [ ] Identify drop-off points
- [ ] A/B test landing page improvements
- [ ] Review user feedback themes

---

## Success Metrics

### Launch Day Goals
- **Product Hunt:**
  - Minimum: Top 20 of the day
  - Target: Top 10 of the day
  - Stretch: Top 5 of the day

- **Hacker News:**
  - Minimum: 20 points
  - Target: Front page (50+ points)
  - Stretch: Top 10 on front page

- **Signups:**
  - Minimum: 200 signups
  - Target: 500 signups
  - Stretch: 1000+ signups

### Week 1 Goals
- **Total signups:** 1000-2000
- **Active users:** 30%+ activation rate (actually installed CLI)
- **Retention:** 50%+ make 2nd commit within week
- **NPS:** Survey first 100 users

### Month 1 Goals
- **Total signups:** 3000-5000
- **Monthly active users:** 500+
- **Revenue:** If paid tier exists, first paying customers
- **Word of mouth:** 20%+ signups from referrals

---

## Red Flags & How to Handle

### If Product Hunt Doesn't Go Well
- Don't panic - HN can still be huge
- Focus energy on Hacker News engagement
- Double down on Reddit communities
- Reach out to beta users for help spreading word

### If Hacker News Doesn't Go Well
- Product Hunt might still succeed
- Focus on developer communities
- Write more technical content
- Engage in HN comments on related posts (build karma)

### If Server Goes Down on Launch Day
- Have Render scale-up plan ready
- Post transparent update: "High traffic, scaling up, back in 10 min"
- Users appreciate honesty
- Fix fast, communicate clearly

### If Criticism is Harsh
- Stay calm and professional
- Acknowledge valid points
- Explain decisions thoughtfully
- Thank critics for feedback
- Fix legitimate issues fast

### If Signups are Low
- Quality > quantity initially
- Focus on activation (get users actually using it)
- Interview users to find PMF issues
- Iterate and relaunch in 4-6 weeks

---

## Launch Assets Checklist

### Required Before Launch
- [ ] Landing page with clear value prop
- [ ] Demo video (under 2 minutes)
- [ ] Product Hunt icon (512x512)
- [ ] Product Hunt gallery (5 images)
- [ ] Working product (no critical bugs)
- [ ] Beta tester testimonials (3-5)
- [ ] FAQ section
- [ ] Support email/channel

### Nice to Have
- [ ] GitHub repo (public or announce date)
- [ ] Blog post
- [ ] Technical deep dive article
- [ ] Twitter account (if using)
- [ ] Logo variations
- [ ] Press kit

---

## Communication Templates

### Product Hunt Response Templates

**Positive Comment:**
```
Thanks so much! 🙏 Really appreciate the support. Let me know if you
try it out - would love to hear your feedback!
```

**Feature Request:**
```
Great suggestion! This is on the roadmap. Out of curiosity, what's
your primary use case? Understanding context helps us prioritize.
```

**Technical Question:**
```
Good question! [Detailed technical answer]. The code for this is here:
[link to GitHub]. Happy to dive deeper if you're curious!
```

**Criticism:**
```
Fair point. [Acknowledge the issue]. Here's our thinking: [explain].
That said, we're definitely open to revisiting this based on feedback.
What would you suggest?
```

### Hacker News Response Templates

**Technical Challenge:**
```
You're absolutely right about [issue]. We considered [alternative
approach] but went with [chosen approach] because [reason].

In retrospect, [acknowledge if they have a point]. Would love to hear
your thoughts on [specific technical question].
```

**Skepticism:**
```
Valid concern. Here's what we learned: [specific data or experience].

That said, we're not claiming to solve [overstated problem]. The goal
is [realistic scope]. Does that address your concern?
```

---

## Week-by-Week Content Calendar

### Pre-Launch (Week -4)
- Mon: Announce beta testing on Indie Hackers
- Wed: Dev.to post: "Building CommitKit: Week 1"
- Fri: Reach out to first 5 beta testers

### Pre-Launch (Week -3)
- Mon: Product Hunt icon design kickoff
- Wed: Record demo video
- Fri: Beta tester testimonial collection

### Pre-Launch (Week -2)
- Mon: Reddit "Ask" post: "How do you track accomplishments?"
- Wed: Dev.to post: "Technical challenges building CommitKit"
- Fri: Finalize launch assets

### Pre-Launch (Week -1)
- Mon: Email waitlist: "Launching this week!"
- Wed: Final testing and bug fixes
- Thu: Product Hunt submission prep
- Fri: Rest before launch

### Launch Week
- Mon: Product Hunt launch
- Mon: Hacker News post
- Mon-Fri: Respond to all feedback
- Fri: "Launch Week Retrospective" post

### Post-Launch (Week 2)
- Mon: First user story published
- Wed: Technical deep dive blog post
- Fri: Feature announcement based on feedback

---

## Optional: Twitter Strategy (If You Choose to Use It)

### Pre-Launch
- Build audience for 4-6 weeks
- Share building journey
- Use hashtags: #buildinpublic #indiehackers
- Engage with dev community

### Launch Day
- Morning thread (10-15 tweets) explaining product
- Share Product Hunt link
- Tag relevant accounts (don't spam)
- Pin launch tweet

### Post-Launch
- Share milestones
- User testimonials
- Technical insights
- Weekly update threads

**If skipping Twitter:** No big deal. Focus energy on Product Hunt, HN, and Reddit instead.

---

## Emergency Contacts / Resources

**If you need help:**
- Product Hunt support: hello@producthunt.com
- Render support: https://render.com/docs/support
- Dev community Slack/Discord servers for troubleshooting

**Monitoring:**
- Render dashboard: https://dashboard.render.com
- Analytics: Google Analytics + Plausible
- Error tracking: Sentry / Rollbar

---

## Post-Launch Retrospective Template

After Week 1, answer these:

1. What worked better than expected?
2. What didn't work at all?
3. What would you do differently?
4. Top 3 pieces of feedback?
5. Most surprising insight?
6. What's next priority?

---

## Final Thoughts

**Remember:**
- Perfect is the enemy of done
- Ship when it works, not when it's perfect
- Respond to users like they're your friends
- Be authentic about why you built this
- Technical depth resonates on HN
- Demo video is worth 1000 words
- Launch day is just day 1

**You've got this!** 🚀
