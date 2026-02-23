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
    3. **Finish and push** - `jj ship`
       - Smart workflow: creates a new change only when the working copy has changes
       - Moves the closest ancestor bookmark to the finished change (or use `--bookmark <name>`)
       - `jj push` runs lints and pushes the bookmark to remote

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
        jj diff --from "trunk()"              # Diff from trunk/main
        jj log -n 20                          # Recent history
        jj status                             # Workspace status
        jj bookmark list                      # List bookmarks
        jj op log                             # Operation history (for undo)
        jj file show <path> -r <rev>          # Preview file contents at revision
        ```

        ## Inspecting Changes

        ### `jj status` vs `jj show`

        **Prefer `jj status`** for routine checks - it shows working copy state concisely:
        - What files are modified/added/deleted
        - Current commit description (if any)
        - Parent commit info

        **Use `jj show` only when necessary** - it displays full commit details including diffs:
        - Shows complete description, author, timestamp
        - Includes full diff output (can be verbose!)
        - Good for: reviewing a specific revision's complete changes
        - Avoid: using as a replacement for `jj status` (unnecessarily verbose)

        ```bash
        # Quick check - PREFERRED for routine use
        jj status

        # View specific revision - use sparingly
        jj show @           # Current working copy details + diff
        jj show @-          # Parent commit details + diff
        jj show main        # Bookmarked revision details

        # Preview file contents at a specific revision (read-only)
        jj file show path/to/file.nix -r main
        ```

        ## Agent-Friendly Command Patterns

        ### Avoiding Interactive Editors

        Many jj commands open `$EDITOR` by default. For automation, use these flags:

        ```bash
        # describe - ALWAYS use -m flag (never open editor)
        jj describe -m "feat(scope): message"      # GOOD
        jj describe                                 # BAD - opens $EDITOR

        # split - provide file paths directly (avoid TUI)
        jj split file1.nix file2.nix               # GOOD - non-interactive
        jj split --interactive                     # BAD - opens TUI

        # squash - use -i only when explicitly requested
        jj squash -i                               # Interactive selection
        jj squash                                  # Squashes all changes from @ into @-
        ```

        ### Model-Friendly Output Flags

        Use these flags to get clean, parseable output:

        ```bash
        # Global flags (work with most commands)
        --no-pager              # Disable pager (essential for automation)
        --color=never           # No ANSI color codes
        --quiet                 # Suppress non-primary output

        # Log-specific flags
        --no-graph              # Linear output without ASCII graph
        -n 20                   # Limit to 20 entries
        -T 'description'        # Custom template (see below)

        # Examples
        jj status --no-pager --color=never
        jj log -n 10 --no-graph --color=never
        jj log -r @ --no-graph -T 'commit_id ++ " " ++ description'
        ```

        ### Useful Templates for Automation

        ```bash
        # Just descriptions (for changelog generation)
        jj log -r "ancestors(@)" --no-graph -T 'description'

        # Compact one-line format
        jj log -r "all()" -n 20 --no-graph -T 'commit_id.short() ++ " " ++ description.first_line()'

        # Show only changed files (no diffs)
        jj show @ --stat
        jj show @ --name-only
        ```

    ## User Aliases

    - `jj df` - diff from trunk
    - `jj tug` - move closest ancestor bookmark to @- (parent of working copy)
    - `jj ch` - fuzzy-pick a bookmark and create new change on it
    - `jj ll` - log ancestors and descendants of current change
    - `jj lint` - run repo-configured lints (without pushing)
    - `jj push` - run repo-configured lints, then push (see below)
    - `jj ship` - finish and push current work (smart: skips new/tug when already empty)
    - `jj sync` - fetch and rebase onto closest ancestor bookmark's remote

        ## Bookmark Workflow

        ```bash
        # Finishing a change and pushing (one-step workflow)
        jj ship                             # Finish and push using closest ancestor bookmark
        jj ship --bookmark main             # Force a specific bookmark
        jj ship --bookmark main@origin      # Use an explicit remote ref
        jj sync                             # Fetch and rebase onto closest ancestor bookmark's remote
        jj sync --bookmark main             # Sync against a specific bookmark

        # Or do it step by step:
        jj new && jj tug                    # Finish change, move bookmark to @-
        jj push                             # Run lints and push (preferred)
        jj git push                         # Push directly, skip lints

            # Manual bookmark management
            jj bookmark set <name>              # Create/move bookmark to @
            jj bookmark set <name> -r @-        # Move bookmark to parent
            jj git push --bookmark <name>       # Push specific bookmark
            ```

        ## Bookmark Display Notation

        In `jj log` and `jj bookmark list` output, the `*` suffix on a bookmark name
        is **display notation only** — it means the bookmark is ahead of its remote
        tracking ref (i.e. has unpushed commits). It is NOT a literal bookmark name.

        ```
        ○  tsumztmr  main*   # "main*" means main is ahead of @origin — NOT a bookmark called "main*"
        ◆  pyplxumy  main@origin
        ```

        ## Conflicted Bookmarks

        > **Note:** This is distinct from a *change conflict* (where file contents
        > conflict due to incompatible edits). A conflicted bookmark is purely a
        > ref-tracking issue — the files themselves are fine.

        A bookmark becomes **conflicted** when two divergent commits both claim it
        (e.g. a commit made via raw git moves the ref independently of jj's tracking).
        `jj bookmark list` shows it as:

        ```
        main (conflicted):
          + abc1234 some commit
          + def5678 another commit
          @origin: def5678 another commit
        ```

        **Do not blindly pick one tip and discard the other — that loses work.**

        Instead, inspect both tips with `jj show <rev>` and determine their relationship:

        1. **Preferred: rebase to form linear history.** If both tips contain real work,
           rebase the newer/local change on top of the other so nothing is lost:
           ```bash
           jj rebase -r <local-tip> -d <other-tip>
           jj bookmark set main -r <local-tip>   # after rebase, use the new commit ID
           ```

        2. **Only discard a tip if you are certain it contains no new work** (e.g. it's
           a duplicate, an empty commit, or already incorporated elsewhere).
           ```bash
           jj bookmark set main -r <correct-rev>
           ```

        3. **If unsure, ask the user** before resolving — show them both tips and their
           contents so they can decide.

        ### Rogue `main*` Bookmark

        In rare cases a literal bookmark named `main*` (with an asterisk) can be
        created when a conflicted bookmark state is mishandled. Git rejects it with:

        ```
        fatal: invalid refspec '...:refs/heads/main*'
        ```

        **Diagnose:**
        ```bash
        jj bookmark list --all-remotes   # Look for a bookmark literally named "main*"
        ```

        **Fix:**
        ```bash
        jj bookmark delete 'main*'       # Quote the name to avoid shell glob expansion
        jj bookmark set main -r <rev>    # Restore main if it was also deleted (see below)
        ```

        > **Warning:** `jj bookmark delete` will delete ALL bookmarks pointing to the
        > same revision. If `main` and `main*` point to the same commit, both get
        > deleted. Restore with `jj bookmark set main -r <rev>` immediately after.

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

        When scripting or parsing jj output, always use these flags:

        ```bash
        # Essential for automation
        --no-pager              # Prevent interactive pager (less)
        --color=never           # Disable ANSI color codes
        --quiet                 # Reduce verbosity

        # Combine for clean, parseable output
        jj log -n 20 --no-pager --color=never --no-graph
        jj status --no-pager --color=never
        jj diff --no-pager --color=never
        ```

        ## Configuration Locations

        | Config | Location | Purpose |
        |--------|----------|---------|
        | User | `~/.jj/config.toml` | Global user settings (name, email, aliases) |
        | Repo | `.jj/repo/config.toml` | Per-repository settings (push-lints, etc.) |
        | VCS | `.jj-lint.toml` | Repository-configured lint commands (VCS-tracked) |
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
