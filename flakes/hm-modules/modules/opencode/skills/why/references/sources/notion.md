# Notion docs

## What this source contains

- Old PRDs (product requirement documents) from the pre-AI era
- Old RFCs from the pre-AI era

Notion mainly contains old RFCs and PRDs in this setup. Current decisions and specs live primarily in repository Markdown files and Linear. Use Notion when the decision dates from the pre-AI era, another source points to an old RFC or PRD, or the user names or links a Notion page.

## How to search it

Search repository Markdown first for current docs. Search Linear for current product and project context. Then use the available Notion skill, CLI, or integration for old RFCs and PRDs. If the user points to Notion, inspect that page or search scope directly regardless of its age or type. Inspect the tool's instructions or help rather than assuming a command or MCP schema.

1. **Run keyword searches through the discovered interface, following its skill instructions or command help.** Try:
   - The feature name
   - Key symbols / class names from the target code
   - Time-bounded queries if you know when the code shipped
   - Historical RFC and PRD titles from the target's era
2. **Retrieve candidate pages through that interface.** Read the full content, not the preview; rationale is often buried mid-document.
3. **Follow backlinks and child pages.** Design docs often have sub-pages for alternatives considered, appendices, or implementation notes.
4. **Check page status and dates.** Distinguish drafts from final documents, and prefer pages from the target's era over unrelated newer material.

## What good evidence looks like here

- A PRD with a "Problem statement" or "Motivation" section that matches the target code's purpose
- An "Alternatives considered" or "Rejected approaches" section
- An RFC that records "we decided X because Y" and ties to the same date range as the PR

## Common pitfalls

- **Outdated docs.** Specs are often written before implementation and not updated; the doc may describe a plan that changed. Cross-check against the actual PR.
- **Doc vs. reality drift.** A spec may say "we'll do X" but the code actually does Y. Flag the divergence; the synthesizer will surface the contradiction.
- **Boilerplate templates.** Some orgs require a "Why" section that gets filled with fluff. Look for specificity.
- **Unlinked docs.** The most relevant doc may not be linked from anywhere. Broad keyword searches help.
- **Multiple drafts.** If a topic has multiple docs, find the one that was finalized or most recently updated. Check dates.
- **Access-restricted pages.** If you can't access a page, note it as a gap.

## What to return

For each relevant doc:
- Title and URL
- Authors and last-updated date
- The motivation text (verbatim quote), with page/section location
- Relevant linked pages (so the synthesizer can cite them)
- Whether the doc was finalized or draft
