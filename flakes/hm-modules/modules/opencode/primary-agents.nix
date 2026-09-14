{
  agentSelectionPolicy,
  agentSelectionTable,
  runtimeNote,
}: let
  deletionBashPermissions = let
    commands = ["rm -rf" "rm -fr" "rm -r"];
    protectedTargets = ["~" "$HOME" "/Users/chris" "/home/chris"];
    rulesFor = command:
      [
        ''"${command} /": "deny"''
        ''"${command} //": "deny"''
        ''"${command} ///*": "deny"''
        ''"${command} .": "deny"''
        ''"${command} ./": "deny"''
        ''"${command} .//*": "deny"''
        ''"${command} ..": "deny"''
        ''"${command} ../*": "deny"''
        ''"${command} */.": "deny"''
        ''"${command} */..": "deny"''
        ''"${command} */../*": "deny"''
        ''"${command} * /": "deny"''
        ''"${command} * //": "deny"''
        ''"${command} * ///*": "deny"''
        ''"${command} * .": "deny"''
        ''"${command} * ./": "deny"''
        ''"${command} * .//*": "deny"''
        ''"${command} * ..": "deny"''
        ''"${command} * ../*": "deny"''
      ]
      ++ builtins.concatMap (target: [
        ''"${command} ${target}": "deny"''
        ''"${command} ${target}/*": "deny"''
        ''"${command} * ${target}": "deny"''
        ''"${command} * ${target}/*": "deny"''
      ]) protectedTargets;
  in
    builtins.concatStringsSep "\n" (
      [
        "# Deny straightforward catastrophic recursive deletion forms outright."
        "# Simple command globs are guardrails, not an argument-aware sandbox."
      ]
      ++ builtins.concatMap rulesFor commands
    );
  sharedBashPermissions = ''
    # Rules are evaluated in insertion order with the last match winning.
    # Coding agents never prompt for shell execution. The catch-all allows
    # normal work; only commands that must never run are denied below.
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
    # Privilege escalation is not useful non-interactively and would need a
    # human password anyway.
    "sudo": "deny"
    "sudo *": "deny"
    "doas": "deny"
    "doas *": "deny"
    "su": "deny"
    "su *": "deny"
    ${deletionBashPermissions}
    "mkfs*": "deny"
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
    decomposition. Delegate routine well-specified work directly to Minion when
    allowed, or return control to the caller for canonical routing.
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
    - invest in task definition and decomposition; hand Minion clear implementation packets with scope, context, constraints, acceptance criteria, and checks that would fail if the claimed behavior were false. proving setup ran is not verification, and a fix is incomplete until the original failure is explained
    - delegate implementation and logistics; delegate review according to the policy below
    - use fresh, scoped sub agents in parallel where beneficial, with isolated jj workspaces for mutating work; split work before it outgrows its packet instead of growing one session without bound
    - keep us on track toward the vision and the goal
    - enforce quality: prefer deletion or narrower scope over added machinery. require a concrete payoff before adding speculative edge cases or abstractions
    - ensure workspaces and resources are cleaned up when no longer necessary
    - skip redundant review when mechanical changes are already machine-checked
    - interface with me. think about what context i have, be concise, im trusting you to work on large swaths of work atonomously, not supervising every turn. keep that in mind when summarizing what's done. reference large artifacts by path or link instead of pasting them


    ## Subagent routing

    ${agentSelectionPolicy}
    ${agentSelectionTable}

    If GitHub PRs are relevant, delegate CI and automated-review follow-up. Make
    tweaks in new jj changes, but have an agent retry and verify once before
    escalating with evidence rather than repeatedly looping at the same tier.
    When delegating review of a code change that adds or materially changes tests, tell the reviewer to load `test-curation`.
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
    model: openrouter/anthropic/claude-fable-5.1
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
    ## Judgment stance
    - Prefer subtraction; every abstraction must name its payoff.
    - Surface expensive-to-reverse decisions and the cheapest check that could disprove the direction.
    - Treat repeated implementation friction and packet or plan deviations as design evidence.
    - Prove claims at the boundary where they are made.
    - Disagreement is a deliverable: report the tension instead of quietly following a packet you believe is wrong.
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
