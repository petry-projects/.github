# Feature Ideation — Reputable Source List

> **Purpose:** A curated, periodically-scanned list of reputable web pages,
> RSS feeds, podcasts, and YouTube channels that the BMAD Analyst (Mary)
> consults during **Phase 2: Market Research** of the
> [Feature Ideation workflow](../.github/workflows/feature-ideation-reusable.yml).
>
> **How it is used:** The reusable workflow checks out this repository into
> `.petry-standards/` on the runner before invoking Claude. The Phase 2
> prompt instructs Mary to read this file and prefer these sources as
> starting points for her web research, supplementing them with targeted
> searches as needed.
>
> **Curation rules:**
>
> - Only sources with a track record of accurate, technically-grounded
>   content. No SEO farms, no anonymous aggregators with no editorial
>   standards.
> - Prefer **primary sources** (vendor changelogs, research labs, official
>   blogs) over secondary commentary.
> - RSS / Atom feed URLs are listed where available — they let Mary fetch
>   structured "what is new since last scan" data instead of scraping HTML.
> - YouTube and podcast feeds are included because release announcements,
>   conference talks, and engineering deep-dives often appear there before
>   (or instead of) blog posts.
> - Every entry has a one-line note explaining **why it is on this list** —
>   if you cannot justify it in one line, it should not be here.
>
> **Maintenance:** Add or remove entries via PR. Treat this file the same
> as `standards/ci-standards.md`: changes propagate to every BMAD-enabled
> repo on its next scheduled run, so review carefully.

---

## 1. AI / ML — Vendor & Lab Primary Sources

Release notes, model launches, capability changes. These are usually the
**first** place a new feature surfaces, weeks before commentary catches up.

| Source | URL | Feed | Why it's here |
|--------|-----|------|---------------|
| Anthropic News | <https://www.anthropic.com/news> | — | Claude model releases, Claude Code changelog, safety research |
| Anthropic Engineering | <https://www.anthropic.com/engineering> | — | Deep dives on agent design, prompting, evals |
| OpenAI Blog | <https://openai.com/blog> | — | GPT / API / product launches |
| Google DeepMind Blog | <https://deepmind.google/discover/blog/> | — | Gemini, AlphaFold, research milestones |
| Google AI / Research Blog | <https://research.google/blog/> | — | Google-wide AI research |
| Meta AI Blog | <https://ai.meta.com/blog/> | — | Llama releases, FAIR research |
| Mistral News | <https://mistral.ai/news/> | — | Open-weights model releases, API changes |
| Hugging Face Blog | <https://huggingface.co/blog> | <https://huggingface.co/blog/feed.xml> | Open-source model launches, training techniques |
| Cohere Blog | <https://cohere.com/blog> | — | Enterprise LLM features, RAG patterns |
| xAI News | <https://x.ai/news> | — | Grok releases, capability updates |

## 2. AI / ML — Research & Trends

Pre-prints, paper trackers, and analyst commentary. Useful for spotting
emerging capabilities **before** they hit vendor APIs.

| Source | URL | Feed | Why it's here |
|--------|-----|------|---------------|
| arXiv cs.AI | <https://arxiv.org/list/cs.AI/recent> | <http://export.arxiv.org/rss/cs.AI> | Daily AI pre-prints |
| arXiv cs.CL | <https://arxiv.org/list/cs.CL/recent> | <http://export.arxiv.org/rss/cs.CL> | NLP / language model pre-prints |
| arXiv cs.LG | <https://arxiv.org/list/cs.LG/recent> | <http://export.arxiv.org/rss/cs.LG> | Machine learning pre-prints |
| Papers with Code — Trending | <https://paperswithcode.com/> | — | Papers ranked by community attention with reference implementations |
| Import AI (Jack Clark) | <https://importai.substack.com/> | <https://importai.substack.com/feed> | Weekly research roundup with policy + capability framing |
| The Gradient | <https://thegradient.pub/> | <https://thegradient.pub/rss/> | Long-form ML research essays |

## 3. Developer Tooling, DevEx & Platform Changelogs

Platform features that unlock new product capabilities. GitHub's changelog
in particular is the **single most important feed** for any project hosted
on GitHub — features ship there weekly and many (Actions, Codespaces,
Discussions APIs) are directly relevant to org workflows.

| Source | URL | Feed | Why it's here |
|--------|-----|------|---------------|
| GitHub Changelog | <https://github.blog/changelog/> | <https://github.blog/changelog/feed/> | Weekly platform feature releases |
| GitHub Engineering Blog | <https://github.blog/category/engineering/> | <https://github.blog/feed/> | How GitHub itself ships things — patterns we can borrow |
| GitLab Releases | <https://about.gitlab.com/releases/categories/releases/> | — | Cross-check competitor features against GitHub |
| Vercel Changelog | <https://vercel.com/changelog> | <https://vercel.com/atom> | Platform / framework features (Next.js, edge, AI SDK) |
| Cloudflare Blog | <https://blog.cloudflare.com/> | <https://blog.cloudflare.com/rss/> | Workers, edge AI, platform infrastructure |
| AWS What's New | <https://aws.amazon.com/new/> | <https://aws.amazon.com/about-aws/whats-new/recent/feed/> | Daily AWS service launches |
| Google Cloud Release Notes | <https://cloud.google.com/release-notes> | — | GCP service launches |
| Stack Overflow Blog | <https://stackoverflow.blog/> | <https://stackoverflow.blog/feed/> | Developer trends, survey data, ecosystem shifts |
| The Pragmatic Engineer | <https://newsletter.pragmaticengineer.com/> | — | Industry trends, eng leadership, real engineering org case studies |

## 4. Security & Compliance

Vulnerability disclosures, advisory feeds, and compliance shifts. Relevant
to any feature touching auth, secrets, supply chain, or user data.

| Source | URL | Feed | Why it's here |
|--------|-----|------|---------------|
| GitHub Security Blog | <https://github.blog/category/security/> | <https://github.blog/category/security/feed/> | Supply-chain, Dependabot, secret scanning updates |
| GitHub Advisory Database | <https://github.com/advisories> | — | CVEs filtered to GitHub-tracked ecosystems |
| CISA Cybersecurity Advisories | <https://www.cisa.gov/news-events/cybersecurity-advisories> | <https://www.cisa.gov/cybersecurity-advisories/all.xml> | US gov authoritative advisory feed |
| OpenSSF Blog | <https://openssf.org/blog/> | — | Supply-chain security standards (Scorecard, Sigstore, SLSA) |
| Snyk Blog | <https://snyk.io/blog/> | <https://snyk.io/blog/feed/> | Practical SCA / SAST commentary |
| Krebs on Security | <https://krebsonsecurity.com/> | <https://krebsonsecurity.com/feed/> | Industry incidents that shape what users worry about |

## 5. Software Engineering Practice & Industry Analysis

Long-form thinking on what is changing in how software is built. Useful
for the "emerging trends" sub-section of Phase 2.

| Source | URL | Feed | Why it's here |
|--------|-----|------|---------------|
| Hacker News (front page) | <https://news.ycombinator.com/> | <https://hnrss.org/frontpage> | Aggregated dev community attention signal |
| Lobsters | <https://lobste.rs/> | <https://lobste.rs/rss> | Higher-signal-than-HN technical link aggregator |
| Martin Fowler | <https://martinfowler.com/> | <https://martinfowler.com/feed.atom> | Architectural patterns, refactoring, evolutionary design |
| Latent Space | <https://www.latent.space/> | <https://www.latent.space/feed> | AI engineering practice — bridges research and production |
| Simon Willison's Weblog | <https://simonwillison.net/> | <https://simonwillison.net/atom/everything/> | LLM tooling, prompt injection, practical AI dev notes |
| Stratechery | <https://stratechery.com/> | — | Strategic / business analysis of platforms shaping the dev landscape |
| Increment Magazine archive | <https://increment.com/> | — | Engineering practice deep-dives (archived but evergreen) |

## 6. Newsletters

Curated weekly digests. Lower noise than RSS firehoses, higher latency.

| Source | URL | Why it's here |
|--------|-----|---------------|
| TLDR Newsletter | <https://tldr.tech/> | Daily tech / AI / dev summary |
| Ben's Bites | <https://bensbites.com/> | Daily AI launches and tools digest |
| The Rundown AI | <https://www.therundown.ai/> | Daily AI news digest |
| Bytes (JavaScript) | <https://bytes.dev/> | Weekly JS ecosystem digest |
| Python Weekly | <https://www.pythonweekly.com/> | Weekly Python ecosystem digest |
| DevOps Weekly | <https://www.devopsweekly.com/> | Weekly DevOps / platform digest |

## 7. Podcasts

Conference talks, founder interviews, and engineering deep-dives often
land here weeks before written summaries. Mary should treat episode
titles + show notes as searchable signal even without listening.

| Show | URL | Feed | Why it's here |
|------|-----|------|---------------|
| Latent Space Podcast | <https://www.latent.space/podcast> | <https://api.substack.com/feed/podcast/1084089.rss> | AI engineering interviews — practitioners, not hype |
| The Changelog | <https://changelog.com/podcast> | <https://changelog.com/podcast/feed> | Weekly OSS / dev tools interviews |
| Practical AI | <https://changelog.com/practicalai> | <https://changelog.com/practicalai/feed> | Applied ML / production AI |
| a16z Podcast | <https://a16z.com/podcasts/> | <https://feeds.simplecast.com/JGE3yC0V> | Investor view of platform / AI trends |
| The Cognitive Revolution | <https://www.cognitiverevolution.ai/> | — | AI capability interviews — strong on frontier model use cases |
| Lex Fridman Podcast | <https://lexfridman.com/podcast/> | <https://lexfridman.com/feed/podcast/> | Long-form interviews with AI researchers and founders |
| Software Engineering Daily | <https://softwareengineeringdaily.com/> | <https://feeds.feedburner.com/SoftwareEngineeringDaily> | Daily eng-practice interviews |

## 8. YouTube Channels

Demo videos, conference talks, and "I tried X" reviews. Often the **first**
place a new model or tool gets benchmarked against real workflows.

| Channel | URL | Why it's here |
|---------|-----|---------------|
| Fireship | <https://www.youtube.com/@Fireship> | Fast, accurate "X in 100 seconds" coverage of new dev tools |
| ThePrimeagen | <https://www.youtube.com/@ThePrimeagen> | Practitioner takes on dev tools and editor workflows |
| Two Minute Papers | <https://www.youtube.com/@TwoMinutePapers> | Accessible AI research paper summaries |
| Yannic Kilcher | <https://www.youtube.com/@YannicKilcher> | In-depth AI paper walkthroughs |
| AI Explained | <https://www.youtube.com/@aiexplained-official> | Sober capability evals of frontier models |
| Matthew Berman | <https://www.youtube.com/@matthew_berman> | Hands-on tests of new AI tools and agents |
| GitHub | <https://www.youtube.com/@GitHub> | GitHub Universe talks, product launch demos |
| AWS Events | <https://www.youtube.com/@AWSEventsChannel> | re:Invent, Summit talks |

## 9. Conferences (annual — check around event dates)

Conference proceedings and keynote announcements are bursty signal sources.
Mary should weight searches around these dates higher.

| Conference | When (typical) | Track |
|------------|----------------|-------|
| GitHub Universe | October | Platform / DevEx |
| KubeCon + CloudNativeCon | March (EU), November (NA) | Cloud-native infra |
| AWS re:Invent | December | Cloud platform |
| Google Cloud Next | April | Cloud platform / AI |
| NeurIPS | December | ML research |
| ICML | July | ML research |
| ICLR | May | ML research / representation learning |
| Strange Loop archive | (defunct, but archive evergreen) | Eng practice deep-dives |
