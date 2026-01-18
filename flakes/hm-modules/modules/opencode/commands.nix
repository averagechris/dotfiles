{
  commit = ''
    ---
    description: Draft a commit message for current changes
    agent: changelog
    ---

    Analyze the current changes and draft a commit message.

    For jj repos: use `jj diff --from "trunk()"` and `jj log -n 5`
    For git repos: use `git diff --staged` or `git diff HEAD`

    Follow the repo's commit conventions (check AGENTS.md, CONTRIBUTING.md).
    Default to Conventional Commits: `type(scope): short summary`

    Output the exact command for user approval:
    - jj: `jj describe -m "..."`
    - git: `git commit -m "..."`
  '';

  review = ''
    ---
    description: Run a code review on current changes
    agent: quality
    ---

    Review the current changes in this repository:

    1. Detect VCS and get diff:
       - jj: `jj diff --from "trunk()"`
       - git: `git diff HEAD` or `git diff --staged`

    2. Check formatting with appropriate linters for detected languages

    3. Run static analysis tools if available

    4. Identify potential issues:
       - Logic errors and edge cases
       - Security concerns
       - Performance issues
       - Code style violations

    5. Provide a structured review report:
       - Summary of changes
       - Critical issues (must fix)
       - Suggestions (nice to have)
       - Positive notes (what's done well)
  '';

  test = ''
    ---
    description: Run tests and checks for the current project
    agent: quality
    ---

    Detect the project type and run appropriate tests:

    Look for these indicators and run matching commands:
    - package.json: `npm test` or `yarn test` or `bun test`
    - Cargo.toml: `cargo test`, `cargo clippy`
    - pyproject.toml/setup.py: `pytest`, `ruff check`, `mypy`
    - go.mod: `go test ./...`
    - flake.nix: `nix flake check`
    - Justfile: `just test` (if test target exists)
    - Makefile: `make test` (if test target exists)

    Report results with:
    - ✅ Passed checks
    - ❌ Failed checks with error details
    - 💡 Suggestions for fixing failures
  '';

  security = ''
    ---
    description: Run a security audit on the codebase
    agent: security-auditor
    ---

    Perform a security audit of this codebase:

    1. Search for potential secrets (API keys, passwords, tokens)
       - Check common patterns: API_KEY, SECRET, PASSWORD, TOKEN
       - Look in config files, environment files, source code
       - DO NOT read files explicitly marked as secrets

    2. Check for security anti-patterns:
       - Hardcoded credentials
       - SQL injection vulnerabilities
       - XSS vulnerabilities
       - Insecure dependencies

    3. Review configurations:
       - Permission settings
       - Authentication/authorization logic
       - Network exposure

    4. Output a structured report:
       - Critical (immediate action required)
       - High priority
       - Medium priority
       - Recommendations
  '';

  explain = ''
    ---
    description: Explain how a part of the codebase works
    agent: explore
    subtask: true
    ---

    Explain how $ARGUMENTS works in this codebase.

    Be thorough:
    1. Find relevant files and read them
    2. Trace dependencies and call chains
    3. Identify key abstractions and patterns
    4. Provide a clear, structured explanation
    5. Include relevant code snippets
  '';

  plan = ''
    ---
    description: Create an implementation plan for a feature or change
    agent: plan
    ---

    Create a detailed implementation plan for: $ARGUMENTS

    1. Understand the current codebase structure
    2. Identify affected files and modules
    3. Break down into discrete steps
    4. Identify risks and edge cases
    5. Suggest tests to validate the implementation

    Output a structured plan that can be executed step-by-step.
  '';

  refactor = ''
    ---
    description: Suggest refactoring improvements for code
    agent: refactor
    subtask: true
    ---

    Analyze $ARGUMENTS and suggest refactoring improvements.

    Focus on:
    - Code clarity and readability
    - Reducing duplication (DRY)
    - Improving modularity
    - Better naming
    - Simplifying complex logic

    For each suggestion, explain:
    - What to change
    - Why it improves the code
    - Any risks or considerations
  '';
}
