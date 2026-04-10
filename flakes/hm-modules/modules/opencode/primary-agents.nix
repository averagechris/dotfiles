{runtimeNote}: {
  build = ''
    ---
    description: Build agent - full development and code change workflows
    mode: primary
    temperature: 0.0
    maxSteps: 120
    tools:
      bash: true
      write: true
      edit: true
      read: true
      glob: true
      grep: true
      list: true
      patch: true
      webfetch: true
      skill: true
    permission:
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
        "git *": "ask"
        "jj abandon*": "ask"
        "jj bookmark delete*": "ask"
        "jj bookmark list*": "allow"
        "jj bookmark move*": "ask"
        "jj bookmark set*": "ask"
        "jj commit*": "ask"
        "jj config*": "allow"
        "jj describe*": "allow"
        "jj diff*": "allow"
        "jj files*": "allow"
        "jj git fetch*": "ask"
        "jj git push*": "ask"
        "jj log*": "allow"
        "jj new*": "allow"
        "jj op log*": "allow"
        "jj resolve --list*": "allow"
        "jj resolve*": "ask"
        "jj show*": "allow"
        "jj split*": "ask"
        "jj squash*": "ask"
        "jj status*": "allow"
        "jj lint*": "allow"
        "jj rebase*": "ask"
        "jj ship*": "ask"
        "jj sync*": "ask"
        "jj tug*": "allow"
        "jj undo*": "ask"
        "just *": "allow"
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
      skill:
        "*": "allow"
      task:
        "*": "allow"
    ---

    You are the Build primary agent. Use this agent for full development and code change workflows.
    In repositories managed by `jj`, prefer `jj` over git commands. Load the `jj-vcs` skill for guidance.
    ${runtimeNote}
  '';

  plan = ''
    ---
    description: Plan agent - analysis and planning (read-only)
    mode: primary
    temperature: 0.0
    maxSteps: 50
    tools:
      bash: true
      write: false
      edit: false
      read: true
      glob: true
      grep: true
      list: true
      webfetch: true
      skill: true
    permission:
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
        "*": "allow"
    ---

    You are the Plan primary agent. Focus on analysis, planning, and proposing changes without making edits.

    - In repositories managed by `jj`, prefer `jj` over git commands.
    - ${runtimeNote}
    - Structure outputs to match the task — at minimum: what you found, what you propose, and what the risks are.
  '';
}
