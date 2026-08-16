{
  agentSelectionPolicy,
  agentSelectionTable,
  runtimeNote,
}: let
  deletionBashPermissions = {allowAbsoluteTempCleanup ? false}:
    builtins.concatStringsSep "\n" (
      [
        "# Normal relative cleanup beneath the Bash tool workdir is allowed."
        "# Absolute, current-directory, upward, and sensitive targets prompt."
        "# Simple command globs are guardrails, not an argument-aware sandbox."
        ''"rm -rf /": "ask"''
        ''"rm -rf /*": "ask"''
        ''"rm -rf .": "ask"''
        ''"rm -rf ./": "ask"''
        ''"rm -rf ..": "ask"''
        ''"rm -rf ../*": "ask"''
      ]
      ++ (
        if allowAbsoluteTempCleanup
        then [
          "# Permit non-empty descendant paths in trusted temp namespaces. The"
          "# ? keeps the namespace roots themselves behind the absolute-path ask."
          ''"rm -rf /tmp/?*": "allow"''
          ''"rm -rf /private/tmp/?*": "allow"''
          ''"rm -rf /var/folders/*/T/opencode/?*": "allow"''
          ''"rm -rf /private/var/folders/*/T/opencode/?*": "allow"''
        ]
        else []
      )
      ++ [
        # Temp descendant allows must not turn path aliases or traversal back
        # into allows. These generic suffixes also cover ./.. and deeper /../.
        ''"rm -rf */.": "ask"''
        ''"rm -rf */..": "ask"''
        ''"rm -rf */../*": "ask"''
        # Redundant slashes can make apparent temp descendants resolve to their
        # namespace roots. This also catches them as later operands.
        ''"rm -rf *//*": "ask"''
        # Conservatively catch dangerous later operands. Simple command globs
        # cannot identify shell operands in general, but these cover common
        # unquoted multi-target forms after an initially harmless target.
        ''"rm -rf * /": "ask"''
        ''"rm -rf * /*": "ask"''
        ''"rm -rf * .": "ask"''
        ''"rm -rf * ./": "ask"''
        ''"rm -rf * ..": "ask"''
        ''"rm -rf * ../*": "ask"''
        ''"rm -rf ~*": "ask"''
        ''"rm -rf * ~*": "ask"''
        ''"rm -rf $HOME*": "ask"''
        ''"rm -rf * $HOME*": "ask"''
        ''"rm -rf /Users*": "ask"''
        ''"rm -rf * /Users*": "ask"''
        ''"rm -rf *secrets*": "ask"''
        ''"rm -r *secrets*": "ask"''
        ''"rm *secrets*": "ask"''
      ]
    );
  sharedBashPermissions = ''
    # Rules are evaluated in insertion order with the last match winning.
    # Default coding agents to open execution, then put sharp edges behind an
    # approval prompt so rare denies are easier to notice.
    "*": "allow"
    # Never let agents directly inspect encrypted secret material, but allow
    # workflows that create/update encrypted secret files through normal
    # editors or generators.
    "cat *secrets/*.age*": "deny"
    "cat *secrets/**/*": "deny"
    "head *secrets/*.age*": "deny"
    "head *secrets/**/*": "deny"
    "tail *secrets/*.age*": "deny"
    "tail *secrets/**/*": "deny"
    "grep *secrets/*.age*": "deny"
    "grep *secrets/**/*": "deny"
    "rg *secrets/*.age*": "deny"
    "rg *secrets/**/*": "deny"
    "sed *secrets/*.age*": "deny"
    "sed *secrets/**/*": "deny"
    "less *secrets/*.age*": "deny"
    "less *secrets/**/*": "deny"
    "more *secrets/*.age*": "deny"
    "more *secrets/**/*": "deny"
    "*.env*": "ask"
    "* .env*": "ask"
    "agenix*": "ask"
    "sops*": "ask"
    # Privilege escalation is not useful non-interactively and would need a
    # human password anyway.
    "sudo": "deny"
    "sudo *": "deny"
    "doas": "deny"
    "doas *": "deny"
    "su": "deny"
    "su *": "deny"
    # Remote login/copy plus deploy/switch commands should stay explicit.
    "ssh *": "ask"
    "scp *": "ask"
    "rsync *": "ask"
    "nix run .#deploy*": "ask"
    "nix run *#deploy*": "ask"
    "nixos-rebuild switch*": "ask"
    "darwin-rebuild switch*": "ask"
    "nh os switch*": "ask"
    "nh darwin switch*": "ask"
    ${deletionBashPermissions {allowAbsoluteTempCleanup = true;}}
    "chmod *": "ask"
    "chown *": "ask"
    "chgrp *": "ask"
    "mkfs*": "deny"
    "diskutil *": "ask"
    "dd *": "ask"
    # Process/service control can break the running desktop or agents.
    "kill *": "ask"
    "killall *": "ask"
    "pkill *": "ask"
    "systemctl *": "ask"
    "launchctl *": "ask"
    # Keep VCS history/publication operations explicit. Read-only jj and
    # routine checks remain allowed by the default rule.
    "git": "ask"
    "git *": "ask"
    "jj abandon*": "ask"
    "jj bookmark delete*": "ask"
    "jj bookmark move*": "ask"
    "jj bookmark set*": "ask"
    "jj commit*": "ask"
    "jj git push*": "ask"
    "jj push*": "ask"
    "jj ship*": "ask"
    "jj tag-push*": "ask"
    # GitHub org/repo/auth/issue administration is higher-impact than reads
    # and PR review/status commands.
    "gh auth*": "ask"
    "gh org*": "ask"
    "gh issue*": "ask"
    "gh repo*": "ask"
    # Kubernetes secret reads and mutating/session commands stay prompt-gated.
    "kubectl describe *secret*": "ask"
    "kubectl get *secret*": "ask"
    "kubectl apply*": "ask"
    "kubectl annotate*": "ask"
    "kubectl attach*": "ask"
    "kubectl cp*": "ask"
    "kubectl create*": "ask"
    "kubectl debug*": "ask"
    "kubectl delete*": "ask"
    "kubectl drain*": "ask"
    "kubectl edit*": "ask"
    "kubectl exec*": "ask"
    "kubectl expose*": "ask"
    "kubectl label*": "ask"
    "kubectl patch*": "ask"
    "kubectl port-forward*": "ask"
    "kubectl replace*": "ask"
    "kubectl rollout*": "ask"
    "kubectl run*": "ask"
    "kubectl scale*": "ask"
    "kubectl set*": "ask"
    "kubectl taint*": "ask"
  '';
  trimmedSharedBashPermissions = builtins.substring 0 ((builtins.stringLength sharedBashPermissions) - 1) sharedBashPermissions;
  indentedSharedBashPermissions = builtins.replaceStrings ["\n"] ["\n    "] trimmedSharedBashPermissions;
in {
  build = ''
    ---
    description: Capable generalist for broad or ambiguous implementation and review.
    mode: all
    temperature: 0.0
    steps: 9999
    permission:
      read: "allow"
      edit: "allow"
      glob: "allow"
      grep: "allow"
      list: "allow"
      webfetch: "allow"
      bash:
        ${indentedSharedBashPermissions}
      skill:
        "*": "allow"
      task:
        "*": "deny"
        "build": "allow"
        "explore": "allow"
        "luna": "allow"
        "minion": "allow"
        "tiny": "allow"
        "wise": "allow"
    ---

    You are the Build agent. Use this exceptional tier only when unresolved
    ambiguity, breadth, investigation, or coordination remains after reasonable
    decomposition. Route routine well-specified implementation through the
    orchestrator to Minion instead.
    ALWAYS USE `jj` over `git` for version control actions.
    ${runtimeNote}
  '';

  orchestrator = ''
    ---
    description: Delegates ambitious multi-track work across capability and cost tiers.
    mode: all
    temperature: 0.0
    steps: 9999
    permission:
      read: "allow"
      edit: "allow"
      glob: "allow"
      grep: "allow"
      list: "allow"
      webfetch: "allow"
      bash:
        ${indentedSharedBashPermissions}
      skill:
        "*": "allow"
      task:
        "*": "deny"
        "build": "allow"
        "explore": "allow"
        "luna": "allow"
        "minion": "allow"
        "tiny": "allow"
        "wise": "allow"
    ---

    You are an orchestrator agent. Delegation is the name of the game.

    ${runtimeNote}

    ## Your role
    - invest in task definition and decomposition; hand Minion clear implementation packets with scope, context, constraints, acceptance criteria, and checks so it can do the bulk of coding
    - delegate implementation and logistics; delegate review according to the policy below
    - use parallel sub agents in isolated jj workspaces where beneficial
    - keep us on track toward the vision and the goal
    - enforce quality: elegance without being dogmatic, high value tests over 100% coverage. some edge cases aren't worth dealing with. be judicious with my attention and what i'm asked to be responsible for and review.
    - ensure workspaces and resources are cleaned up when no longer necessary
    - skip redundant review when mechanical changes are already machine-checked
    - interface with me. think about what context i have, be concise, im trusting you to work on large swaths of work atonomously, not supervising every turn. keep that in mind when summarizing what's done. provide links to PRs, artifacts, issue tracker tickets, etc when referencing


    ## Subagent routing

    ${agentSelectionPolicy}
    ${agentSelectionTable}

    If GitHub PRs are relevant, delegate CI and automated-review follow-up. Make
    tweaks in new jj changes, but have an agent retry and verify once before
    escalating with evidence rather than repeatedly looping at the same tier.
  '';

  minion = ''
    ---
    description: Cost-effective coder and reviewer for sustained routine work with broader context.
    mode: subagent
    model: openrouter/openai/gpt-5.6-sol
    variant: low
    temperature: 0.0
    steps: 9999
    permission:
      read: "allow"
      edit: "allow"
      glob: "allow"
      grep: "allow"
      list: "allow"
      webfetch: "allow"
      bash:
        ${indentedSharedBashPermissions}
      skill:
        "*": "allow"
      task:
        "*": "deny"
        "explore": "allow"
        "tiny": "allow"
    ---

    You are a coding agent. ALWAYS USE `jj` over `git` for version control actions.
    ${runtimeNote}
  '';

  tiny = ''
    ---
    description: Cheapest delegate for mechanical logistics, exact checks, cleanup, and tiny deterministic edits.
    mode: subagent
    model: openrouter/openai/gpt-5.6-luna
    variant: low
    temperature: 0.0
    steps: 9999
    permission:
      read: "allow"
      edit: "allow"
      glob: "allow"
      grep: "allow"
      list: "allow"
      webfetch: "allow"
      bash:
        ${indentedSharedBashPermissions}
      skill:
        "*": "allow"
      task:
        "*": "deny"
        "build": "allow"
        "explore": "allow"
        "luna": "allow"
        "minion": "allow"
        "tiny": "allow"
        "wise": "allow"
    ---

    You are a coding agent. ALWAYS USE `jj` over `git` for version control actions.
    ${runtimeNote}
  '';

  luna = ''
    ---
    description: Cost-effective delegate for bounded medium-complexity work and deterministic review needing reasoning.
    mode: subagent
    model: openrouter/openai/gpt-5.6-luna
    variant: high
    temperature: 0.0
    steps: 9999
    permission:
      read: "allow"
      edit: "allow"
      glob: "allow"
      grep: "allow"
      list: "allow"
      webfetch: "allow"
      bash:
        ${indentedSharedBashPermissions}
      skill:
        "*": "allow"
      task:
        "*": "deny"
        "build": "allow"
        "explore": "allow"
        "luna": "allow"
        "minion": "allow"
        "tiny": "allow"
        "wise": "allow"
    ---

    You are a coding agent. ALWAYS USE `jj` over `git` for version control actions.
    ${runtimeNote}
  '';

  wise = ''
    ---
    description: Highest-capability delegate for difficult, high-stakes work; expensive.
    mode: subagent
    model: openrouter/anthropic/claude-fable-5
    variant: high
    temperature: 0.0
    steps: 9999
    permission:
      read: "allow"
      edit: "allow"
      glob: "allow"
      grep: "allow"
      list: "allow"
      webfetch: "allow"
      bash:
        ${indentedSharedBashPermissions}
      skill:
        "*": "allow"
      task:
        "*": "deny"
        "build": "allow"
        "explore": "allow"
        "luna": "allow"
        "minion": "allow"
        "tiny": "allow"
        "wise": "allow"
    ---

    You are a coding agent. ALWAYS USE `jj` over `git` for version control actions.
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
        "cat": "allow"
        "cat *": "allow"
        "echo": "allow"
        "echo *": "allow"
        "fd": "allow"
        "fd *": "allow"
        "find": "allow"
        "find *": "allow"
        "grep": "allow"
        "grep *": "allow"
        "head": "allow"
        "head *": "allow"
        "ls": "allow"
        "ls *": "allow"
        "rg": "allow"
        "rg *": "allow"
        "sort": "allow"
        "sort *": "allow"
        "tail": "allow"
        "tail *": "allow"
        "wc": "allow"
        "wc *": "allow"
        "which": "allow"
        "which *": "allow"
        "cargo": "allow"
        "cargo *": "allow"
        "jj bookmark list": "allow"
        "jj bookmark list *": "allow"
        "jj config": "allow"
        "jj config *": "allow"
        "jj diff": "allow"
        "jj diff *": "allow"
        "jj files": "allow"
        "jj files *": "allow"
        "jj log": "allow"
        "jj log *": "allow"
        "jj op log": "allow"
        "jj op log *": "allow"
        "jj resolve --list": "allow"
        "jj resolve --list *": "allow"
        "jj show": "allow"
        "jj show *": "allow"
        "jj status": "allow"
        "jj status *": "allow"
        "nix eval": "allow"
        "nix eval *": "allow"
        "nix flake show": "allow"
        "nix flake show *": "allow"
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
