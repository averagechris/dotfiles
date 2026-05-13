{runtimeNote}: {
  build = ''
    ---
    description: Build agent - full development and code change workflows
    mode: all
    temperature: 0.0
    steps: 120
    permission:
      read: "allow"
      edit: "allow"
      glob: "allow"
      grep: "allow"
      list: "allow"
      webfetch: "allow"
      bash:
        "*": "ask"
        "alejandra*": "allow"
        "awk*": "ask"
        "cat*": "allow"
        "echo*": "allow"
        "fd*": "allow"
        "find*": "allow"
        "grep*": "allow"
        "head*": "allow"
        "ls*": "allow"
        "rg*": "allow"
        "sed*": "allow"
        "sort*": "allow"
        "tail*": "allow"
        "wc*": "allow"
        "which*": "allow"
        "cargo*": "allow"
        "gh *": "allow"
        "gh auth*": "ask"
        "gh org*": "ask"
        "gh issue*": "ask"
        "gh repo*": "ask"
        "linear *": "allow"
        "jj *": "allow"
        "jj abandon*": "ask"
        "jj bookmark delete*": "ask"
        "jj bookmark move*": "ask"
        "jj bookmark set*": "ask"
        "jj commit*": "ask"
        "just": "allow"
        "just *": "allow"
        "make": "allow"
        "make *": "allow"
        "mypy*": "allow"
        "nix*": "allow"
        "nix-instantiate*": "allow"
        "nix-store*": "allow"
        "nixos-rebuild build*": "allow"
        "darwin-rebuild build*": "allow"
        "pre-commit*": "allow"
        "pytest*": "allow"
        "ruff*": "allow"
        "statix*": "allow"
        "surecraft *": "allow"
        "surecraft-*": "allow"
      skill:
        "*": "allow"
      task:
        "*": "deny"
        "build": "allow"
        "explore": "allow"
    ---

    You are the Build primary agent. Use this agent for full development and code change workflows.
    ALWAYS USE `jj` over `git` for version control actions.
    ${runtimeNote}
  '';

  plan = ''
    ---
    description: Plan agent - analysis and planning (read-only)
    mode: primary
    temperature: 0.0
    steps: 50
    permission:
      read: "allow"
      edit: "deny"
      glob: "allow"
      grep: "allow"
      list: "allow"
      webfetch: "allow"
      bash:
        "*": "deny"
        "cat*": "allow"
        "echo*": "allow"
        "fd*": "allow"
        "find*": "allow"
        "grep*": "allow"
        "head*": "allow"
        "ls*": "allow"
        "rg*": "allow"
        "sort*": "allow"
        "tail*": "allow"
        "wc*": "allow"
        "which*": "allow"
        "cargo*": "allow"
        "jj bookmark list*": "allow"
        "jj config*": "allow"
        "jj diff*": "allow"
        "jj files*": "allow"
        "jj log*": "allow"
        "jj op log*": "allow"
        "jj resolve --list*": "allow"
        "jj show*": "allow"
        "jj status*": "allow"
        "nix eval*": "allow"
        "nix flake show*": "allow"
      skill:
        "*": "allow"
      task:
        "*": "deny"
        "build": "allow"
        "explore": "allow"
    ---

    You are the Plan primary agent. Focus on analysis, planning, and proposing changes without making edits.

    - ALWAYS USE `jj` over `git` for version control actions.
    - Structure outputs to match the task — at minimum: what you found, what you propose, and what the risks are.
    - ${runtimeNote}
  '';
}
