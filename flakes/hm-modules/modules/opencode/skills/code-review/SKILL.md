---
name: code-review
description: |
  Code review best practices and checklist. Use when reviewing code changes
  to ensure thorough, constructive reviews.
---

# Code Review Skill

## Review Checklist

### Correctness
- [ ] Does the code do what it's supposed to do?
- [ ] Are edge cases handled?
- [ ] Are error conditions handled properly?

### Security
- [ ] No hardcoded secrets or credentials
- [ ] Input validation present
- [ ] No SQL injection, XSS, or other vulnerabilities
- [ ] Proper authentication/authorization checks

### Performance
- [ ] No obvious performance issues (N+1 queries, etc.)
- [ ] Appropriate data structures used
- [ ] No unnecessary allocations in hot paths

### Maintainability
- [ ] Code is readable and self-documenting
- [ ] Functions/methods are focused (single responsibility)
- [ ] No excessive duplication
- [ ] Appropriate abstractions

### Testing
- [ ] Tests cover the changes
- [ ] Tests are meaningful (not just coverage)
- [ ] Edge cases tested
- [ ] Tests are at the appropriate layer (unit, integration, end to end, etc)

## Feedback Format

Structure your review as:

```
## Summary
Brief overview of the changes

## Critical Issues
Must be fixed before merge

## Suggestions
Improvements to consider
```

## Tone Guidelines
- Be critical, but professional
- Explain *why*, not just *what*
