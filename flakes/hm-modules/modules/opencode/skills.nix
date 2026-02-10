{
  jj-vcs = ''
    ---
    name: jj-vcs
    description: |
      Jujutsu (jj) version control system reference. Use when working with jj repositories,
      managing bookmarks, resolving conflicts, or drafting commit messages.
    ---

    # Jujutsu (jj) VCS Skill

    Use this skill when working with repositories managed by jj (Jujutsu).
    Detect jj repos by checking for `.jj/` directory.

    ## Key Concept: Working Copy

    Unlike git, jj's **working copy IS a commit**. Every file change automatically
    amends the current working copy commit. There's no staging area.

    - `@` always refers to the working copy commit
    - `@-` is the parent of the working copy
    - Changes are saved automatically as you edit files

    ## Typical Workflow

    1. **Work on current change** - Edit files, they're auto-saved to `@`
    2. **Describe when ready** - `jj describe -m "feat: ..."` to set the message
    3. **Finish and push** - `jj new && jj tug` then `jj git push`
       - `jj new` creates empty change on top, making described change `@-`
       - `jj tug` moves the bookmark to `@-` (the finished change)
       - `jj git push` pushes the bookmark to remote

    ### Iterative Squash Pattern

    For building up a change incrementally:
    1. Have a described parent change you're building
    2. Work in a new empty change on top (`jj new`)
    3. Repeatedly `jj squash` to fold work into parent
    4. Abandon the empty working copy or keep iterating

    ### WIP Changes

    It's fine to leave changes undescribed or with "WIP" while iterating.
    Describe them properly before pushing.

    ## Safety Rules

    ### Autonomous Actions (Safe to Run Without Asking)

    **Creating new work** - These are safe because they don't modify existing commits:
    - `jj new` - create a new empty change on top of current
    - `jj describe` - set message for the current working copy commit (`@`)
    - `jj bookmark set <name>` - create a new bookmark on `@` (only when creating new)

    ### Always Ask Before Running

    **Modifying existing history** - These can "smash" previous work:
    - `jj squash` - fold changes into parent (modifies existing commit)
    - `jj split` - split a change into multiple (modifies existing commit)
    - `jj abandon` - abandon a change (loss of work possible)
    - `jj bookmark move/delete` - moving existing bookmarks (changes history)
    - `jj bookmark set <name> -r <rev>` - moving bookmark to specific revision
    - `jj describe -r <rev>` - describing a non-working-copy revision
    - `jj git push` - push to remote (irreversible)
    - `jj resolve` - resolve conflicts (can lose work if wrong)
    - `jj undo` - undo last operation
    - `jj commit` - commit with message in one step

    ### Safe to Run (Read-Only)
    - `jj diff`, `jj log`, `jj status`, `jj show`, `jj files`
    - `jj bookmark list`, `jj config`, `jj op log`, `jj resolve --list`
    - `jj tug` - move closest ancestor bookmark to parent (user convenience alias)

    ## Common Commands

    ```bash
    jj diff --from "trunk()"  # Diff from trunk/main
    jj log -n 20              # Recent history
    jj status                 # Workspace status
    jj show <rev>:path        # Preview file at revision
    jj bookmark list          # List bookmarks
    jj op log                 # Operation history (for undo)
    ```

    ## User Aliases

    - `jj df` - diff from trunk
    - `jj tug` - move closest ancestor bookmark to @- (parent of working copy)
    - `jj ch` - fuzzy-pick a bookmark and create new change on it
    - `jj ll` - log ancestors and descendants of current change
    - `jj lint` - run repo-configured lints (without pushing)
    - `jj push` - run repo-configured lints, then push (see below)

    ## Bookmark Workflow

    ```bash
    # Finishing a change and pushing
    jj new && jj tug                    # Finish change, move bookmark to @-
    jj push                             # Run lints and push (preferred)
    jj git push                         # Push directly, skip lints

    # Manual bookmark management
    jj bookmark set <name>              # Create/move bookmark to @
    jj bookmark set <name> -r @-        # Move bookmark to parent
    jj git push --bookmark <name>       # Push specific bookmark
    ```

    ## Commit Message Style
    Use Conventional Commits: `type(scope): short summary`

    Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore

    Example: `jj describe -m "feat(auth): add OAuth2 support"`

    ## Colocated Workflow (jj + git)
    - jj manages git refs automatically
    - Use `jj git fetch` instead of `git fetch`
    - Use `jj push` (with lints) or `jj git push` (without lints)
    - Avoid raw git commands; they may desync jj

    ## Pre-Push Lints

    The `jj push` alias runs lints before pushing. Configure per-repo in `.jj/repo/config.toml`:

    ```toml
    [dotfiles]
    push-lints = ["alejandra --check .", "statix check"]
    ```

    Examples for other project types:
    ```toml
    # Rust
    push-lints = ["cargo fmt --check", "cargo clippy"]

    # Python
    push-lints = ["ruff check .", "ruff format --check ."]
    ```

    If no lints are configured, `jj push` just pushes without running anything.

    ## Machine-Friendly Output
    - Use `--no-pager` or pipe to `cat`
    - Use `--color=never` when parsing output
  '';

  conventional-commits = ''
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
    | ci | CI configuration | - |
    | chore | Maintenance tasks | - |

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
  '';

  code-review = ''
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

    ## Feedback Format

    Structure your review as:

    ```
    ## Summary
    Brief overview of the changes

    ## Critical Issues
    Must be fixed before merge

    ## Suggestions
    Improvements to consider

    ## Positive Notes
    What's done well (important for morale!)
    ```

    ## Tone Guidelines
    - Be constructive, not critical
    - Explain *why*, not just *what*
    - Ask questions instead of making demands
    - Acknowledge good work
  '';
}
