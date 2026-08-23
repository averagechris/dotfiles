---
name: conventional-commits
description: Use when drafting, reviewing, or correcting commit messages or `jj describe` messages, choosing a commit type or scope, marking breaking changes, or mapping changes to semantic version bumps. Do not use for non-commit prose.
---

# Conventional Commits

Format: `type(scope): description`. Scope is optional and names the codebase section.

## Types

| Type | Meaning | Version bump |
|------|---------|--------------|
| feat | New feature | MINOR |
| fix | Bug fix | PATCH |
| perf | Performance improvement | PATCH |
| docs | Documentation only | none |
| style | Formatting, no code change | none |
| refactor | Code change, no feature/fix | none |
| test | Adding/fixing tests | none |
| build | Build system changes | none |
| chore | Maintenance tasks | none |
| revert | Reverting a change | none |

## Breaking changes

Add `!` after the type or a `BREAKING CHANGE:` footer:

```
feat!: remove deprecated API
feat(api): change response format

BREAKING CHANGE: response is now JSON
```

## Examples

```
feat(api): add user registration endpoint
fix(auth): handle expired tokens correctly
docs(readme): update installation instructions
refactor(db): extract connection pooling logic
test(api): add integration tests for /users
```
