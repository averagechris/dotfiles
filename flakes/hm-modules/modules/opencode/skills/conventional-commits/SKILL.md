---
name: conventional-commits
description: |
  Conventional Commits specification reference. Use when drafting commit messages
  to ensure consistent, semantic versioning-friendly commits.
---

# Conventional Commits

Format: `type(scope): description`

## Types

| Type | Description | Bumps |
|------|-------------|-------|
| feat | New feature | MINOR |
| fix | Bug fix | PATCH |
| docs | Documentation only | - |
| style | Formatting, no code change | - |
| refactor | Code change, no feature/fix | - |
| perf | Performance improvement | PATCH |
| test | Adding/fixing tests | - |
| build | Build system changes | - |
| chore | Maintenance tasks | - |
| revert | Reverting a change | - |

## Breaking Changes

Add `!` after type or `BREAKING CHANGE:` in footer:
- `feat!: remove deprecated API`
- `feat(api): change response format\n\nBREAKING CHANGE: response is now JSON`

## Scope

Optional, describes the section of codebase:
- `feat(auth): add login endpoint`
- `fix(ui): correct button alignment`

## Examples

```
feat(api): add user registration endpoint
fix(auth): handle expired tokens correctly
docs(readme): update installation instructions
refactor(db): extract connection pooling logic
test(api): add integration tests for /users
```
