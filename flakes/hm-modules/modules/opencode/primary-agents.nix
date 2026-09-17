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
        ''          - action: shell
            resource: "${command} /"
            effect: deny''
        ''          - action: shell
            resource: "${command} //"
            effect: deny''
        ''          - action: shell
            resource: "${command} ///*"
            effect: deny''
        ''          - action: shell
            resource: "${command} ."
            effect: deny''
        ''          - action: shell
            resource: "${command} ./"
            effect: deny''
        ''          - action: shell
            resource: "${command} .//*"
            effect: deny''
        ''          - action: shell
            resource: "${command} .."
            effect: deny''
        ''          - action: shell
            resource: "${command} ../*"
            effect: deny''
        ''          - action: shell
            resource: "${command} */."
            effect: deny''
        ''          - action: shell
            resource: "${command} */.."
            effect: deny''
        ''          - action: shell
            resource: "${command} */../*"
            effect: deny''
        ''          - action: shell
            resource: "${command} * /"
            effect: deny''
        ''          - action: shell
            resource: "${command} * //"
            effect: deny''
        ''          - action: shell
            resource: "${command} * ///*"
            effect: deny''
        ''          - action: shell
            resource: "${command} * ."
            effect: deny''
        ''          - action: shell
            resource: "${command} * ./"
            effect: deny''
        ''          - action: shell
            resource: "${command} * .//*"
            effect: deny''
        ''          - action: shell
            resource: "${command} * .."
            effect: deny''
        ''          - action: shell
            resource: "${command} * ../*"
            effect: deny''
      ]
      ++ builtins.concatMap (target: [
        ''          - action: shell
            resource: "${command} ${target}"
            effect: deny''
        ''          - action: shell
            resource: "${command} ${target}/*"
            effect: deny''
        ''          - action: shell
            resource: "${command} * ${target}"
            effect: deny''
        ''          - action: shell
            resource: "${command} * ${target}/*"
            effect: deny''
      ])
      protectedTargets;
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
    - action: shell
      resource: "*"
      effect: allow
    # Never let agents directly inspect encrypted secret material, but allow
    # workflows that create/update encrypted secret files through normal
    # editors or generators.
    - action: shell
      resource: "cat *secrets/*.age*"
      effect: deny
    - action: shell
      resource: "cat *secrets/**/*"
      effect: deny
    - action: shell
      resource: "head *secrets/*.age*"
      effect: deny
    - action: shell
      resource: "head *secrets/**/*"
      effect: deny
    - action: shell
      resource: "tail *secrets/*.age*"
      effect: deny
    - action: shell
      resource: "tail *secrets/**/*"
      effect: deny
    - action: shell
      resource: "grep *secrets/*.age*"
      effect: deny
    - action: shell
      resource: "grep *secrets/**/*"
      effect: deny
    - action: shell
      resource: "rg *secrets/*.age*"
      effect: deny
    - action: shell
      resource: "rg *secrets/**/*"
      effect: deny
    - action: shell
      resource: "sed *secrets/*.age*"
      effect: deny
    - action: shell
      resource: "sed *secrets/**/*"
      effect: deny
    - action: shell
      resource: "less *secrets/*.age*"
      effect: deny
    - action: shell
      resource: "less *secrets/**/*"
      effect: deny
    - action: shell
      resource: "more *secrets/*.age*"
      effect: deny
    - action: shell
      resource: "more *secrets/**/*"
      effect: deny
    # Privilege escalation is not useful non-interactively and would need a
    # human password anyway.
    - action: shell
      resource: "sudo"
      effect: deny
    - action: shell
      resource: "sudo *"
      effect: deny
    - action: shell
      resource: "doas"
      effect: deny
    - action: shell
      resource: "doas *"
      effect: deny
    - action: shell
      resource: "su"
      effect: deny
    - action: shell
      resource: "su *"
      effect: deny
    ${deletionBashPermissions}
    - action: shell
      resource: "mkfs*"
      effect: deny
  '';
  trimmedSharedBashPermissions = builtins.substring 0 ((builtins.stringLength sharedBashPermissions) - 1) sharedBashPermissions;
  indentedSharedBashPermissions = builtins.replaceStrings ["\n"] ["\n  "] trimmedSharedBashPermissions;
in {
  build = ''
    ---
    description: Capable generalist for broad or ambiguous implementation and review.
    mode: all
    request:
      body:
        temperature: 0.0
    steps: 9999
    permissions:
      - action: read
        resource: "*"
        effect: allow
      - action: edit
        resource: "*"
        effect: allow
      - action: glob
        resource: "*"
        effect: allow
      - action: grep
        resource: "*"
        effect: allow
      - action: list
        resource: "*"
        effect: allow
      - action: webfetch
        resource: "*"
        effect: allow
      ${indentedSharedBashPermissions}
      - action: skill
        resource: "*"
        effect: allow
      - action: subagent
        resource: "*"
        effect: deny
      - action: subagent
        resource: "build"
        effect: allow
      - action: subagent
        resource: "explore"
        effect: allow
      - action: subagent
        resource: "luna"
        effect: allow
      - action: subagent
        resource: "minion"
        effect: allow
      - action: subagent
        resource: "tiny"
        effect: allow
      - action: subagent
        resource: "wise"
        effect: allow
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
    request:
      body:
        temperature: 0.0
    steps: 9999
    permissions:
      - action: read
        resource: "*"
        effect: allow
      - action: edit
        resource: "*"
        effect: allow
      - action: glob
        resource: "*"
        effect: allow
      - action: grep
        resource: "*"
        effect: allow
      - action: list
        resource: "*"
        effect: allow
      - action: webfetch
        resource: "*"
        effect: allow
      ${indentedSharedBashPermissions}
      - action: skill
        resource: "*"
        effect: allow
      - action: subagent
        resource: "*"
        effect: deny
      - action: subagent
        resource: "build"
        effect: allow
      - action: subagent
        resource: "explore"
        effect: allow
      - action: subagent
        resource: "luna"
        effect: allow
      - action: subagent
        resource: "minion"
        effect: allow
      - action: subagent
        resource: "tiny"
        effect: allow
      - action: subagent
        resource: "wise"
        effect: allow
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

    ## Jujutsu skill routing

    | Work | Owning skill |
    | --- | --- |
    | Local change shaping | `jj-change-management` |
    | Conflict resolution | `jj-conflict-resolution` |
    | Lint, sync, push, or ship | `jj-repo-workflow` |
    | Repository acquisition or isolated checkouts | `bay-workspaces` |
    | GitHub PR work on suremac | `suremac-jj-pr` |

    Do not copy command manuals into handoffs. Every mutating handoff for
    isolated work must name the exact Bay workspace path.

    If GitHub PRs are relevant, delegate CI and automated-review follow-up. Make
    tweaks in new jj changes, but have an agent retry and verify once before
    escalating with evidence rather than repeatedly looping at the same tier.
    When delegating review of a code change that adds or materially changes tests, tell the reviewer to load `test-curation`.
  '';

  minion = ''
    ---
    description: Cost-effective coder and reviewer for sustained routine work with broader context.
    mode: subagent
    model: openrouter/openai/gpt-5.6-sol#low
    request:
      body:
        temperature: 0.0
    steps: 9999
    permissions:
      - action: read
        resource: "*"
        effect: allow
      - action: edit
        resource: "*"
        effect: allow
      - action: glob
        resource: "*"
        effect: allow
      - action: grep
        resource: "*"
        effect: allow
      - action: list
        resource: "*"
        effect: allow
      - action: webfetch
        resource: "*"
        effect: allow
      ${indentedSharedBashPermissions}
      - action: skill
        resource: "*"
        effect: allow
      - action: subagent
        resource: "*"
        effect: deny
      - action: subagent
        resource: "explore"
        effect: allow
      - action: subagent
        resource: "tiny"
        effect: allow
    ---

    You are a coding agent. ALWAYS USE `jj` over `git` for version control actions.
    ${runtimeNote}
  '';

  tiny = ''
    ---
    description: Cheapest delegate for mechanical logistics, exact checks, cleanup, and tiny deterministic edits.
    mode: subagent
    model: openrouter/openai/gpt-5.6-luna#low
    request:
      body:
        temperature: 0.0
    steps: 9999
    permissions:
      - action: read
        resource: "*"
        effect: allow
      - action: edit
        resource: "*"
        effect: allow
      - action: glob
        resource: "*"
        effect: allow
      - action: grep
        resource: "*"
        effect: allow
      - action: list
        resource: "*"
        effect: allow
      - action: webfetch
        resource: "*"
        effect: allow
      ${indentedSharedBashPermissions}
      - action: skill
        resource: "*"
        effect: allow
      - action: subagent
        resource: "*"
        effect: deny
      - action: subagent
        resource: "build"
        effect: allow
      - action: subagent
        resource: "explore"
        effect: allow
      - action: subagent
        resource: "luna"
        effect: allow
      - action: subagent
        resource: "minion"
        effect: allow
      - action: subagent
        resource: "tiny"
        effect: allow
      - action: subagent
        resource: "wise"
        effect: allow
    ---

    You are a coding agent. ALWAYS USE `jj` over `git` for version control actions.
    ${runtimeNote}
  '';

  luna = ''
    ---
    description: Cost-effective delegate for bounded medium-complexity work and deterministic review needing reasoning.
    mode: subagent
    model: openrouter/openai/gpt-5.6-luna#high
    request:
      body:
        temperature: 0.0
    steps: 9999
    permissions:
      - action: read
        resource: "*"
        effect: allow
      - action: edit
        resource: "*"
        effect: allow
      - action: glob
        resource: "*"
        effect: allow
      - action: grep
        resource: "*"
        effect: allow
      - action: list
        resource: "*"
        effect: allow
      - action: webfetch
        resource: "*"
        effect: allow
      ${indentedSharedBashPermissions}
      - action: skill
        resource: "*"
        effect: allow
      - action: subagent
        resource: "*"
        effect: deny
      - action: subagent
        resource: "build"
        effect: allow
      - action: subagent
        resource: "explore"
        effect: allow
      - action: subagent
        resource: "luna"
        effect: allow
      - action: subagent
        resource: "minion"
        effect: allow
      - action: subagent
        resource: "tiny"
        effect: allow
      - action: subagent
        resource: "wise"
        effect: allow
    ---

    You are a coding agent. ALWAYS USE `jj` over `git` for version control actions.
    ${runtimeNote}
  '';

  wise = ''
    ---
    description: Highest-capability delegate for difficult, high-stakes work; expensive.
    mode: subagent
    model: openrouter/anthropic/claude-fable-5.1#high
    request:
      body:
        temperature: 0.0
    steps: 9999
    permissions:
      - action: read
        resource: "*"
        effect: allow
      - action: edit
        resource: "*"
        effect: allow
      - action: glob
        resource: "*"
        effect: allow
      - action: grep
        resource: "*"
        effect: allow
      - action: list
        resource: "*"
        effect: allow
      - action: webfetch
        resource: "*"
        effect: allow
      ${indentedSharedBashPermissions}
      - action: skill
        resource: "*"
        effect: allow
      - action: subagent
        resource: "*"
        effect: deny
      - action: subagent
        resource: "build"
        effect: allow
      - action: subagent
        resource: "explore"
        effect: allow
      - action: subagent
        resource: "luna"
        effect: allow
      - action: subagent
        resource: "minion"
        effect: allow
      - action: subagent
        resource: "tiny"
        effect: allow
      - action: subagent
        resource: "wise"
        effect: allow
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
    request:
      body:
        temperature: 0.0
    steps: 50
    permissions:
      - action: read
        resource: "*"
        effect: allow
      - action: edit
        resource: "*"
        effect: deny
      - action: glob
        resource: "*"
        effect: allow
      - action: grep
        resource: "*"
        effect: allow
      - action: list
        resource: "*"
        effect: allow
      - action: webfetch
        resource: "*"
        effect: allow
      - action: shell
        resource: "*"
        effect: deny
      - action: shell
        resource: "cat"
        effect: allow
      - action: shell
        resource: "cat *"
        effect: allow
      - action: shell
        resource: "echo"
        effect: allow
      - action: shell
        resource: "echo *"
        effect: allow
      - action: shell
        resource: "fd"
        effect: allow
      - action: shell
        resource: "fd *"
        effect: allow
      - action: shell
        resource: "find"
        effect: allow
      - action: shell
        resource: "find *"
        effect: allow
      - action: shell
        resource: "grep"
        effect: allow
      - action: shell
        resource: "grep *"
        effect: allow
      - action: shell
        resource: "head"
        effect: allow
      - action: shell
        resource: "head *"
        effect: allow
      - action: shell
        resource: "ls"
        effect: allow
      - action: shell
        resource: "ls *"
        effect: allow
      - action: shell
        resource: "rg"
        effect: allow
      - action: shell
        resource: "rg *"
        effect: allow
      - action: shell
        resource: "sort"
        effect: allow
      - action: shell
        resource: "sort *"
        effect: allow
      - action: shell
        resource: "tail"
        effect: allow
      - action: shell
        resource: "tail *"
        effect: allow
      - action: shell
        resource: "wc"
        effect: allow
      - action: shell
        resource: "wc *"
        effect: allow
      - action: shell
        resource: "which"
        effect: allow
      - action: shell
        resource: "which *"
        effect: allow
      - action: shell
        resource: "cargo"
        effect: allow
      - action: shell
        resource: "cargo *"
        effect: allow
      - action: shell
        resource: "jj bookmark list"
        effect: allow
      - action: shell
        resource: "jj bookmark list *"
        effect: allow
      - action: shell
        resource: "jj config"
        effect: allow
      - action: shell
        resource: "jj config *"
        effect: allow
      - action: shell
        resource: "jj diff"
        effect: allow
      - action: shell
        resource: "jj diff *"
        effect: allow
      - action: shell
        resource: "jj files"
        effect: allow
      - action: shell
        resource: "jj files *"
        effect: allow
      - action: shell
        resource: "jj log"
        effect: allow
      - action: shell
        resource: "jj log *"
        effect: allow
      - action: shell
        resource: "jj op log"
        effect: allow
      - action: shell
        resource: "jj op log *"
        effect: allow
      - action: shell
        resource: "jj resolve --list"
        effect: allow
      - action: shell
        resource: "jj resolve --list *"
        effect: allow
      - action: shell
        resource: "jj show"
        effect: allow
      - action: shell
        resource: "jj show *"
        effect: allow
      - action: shell
        resource: "jj status"
        effect: allow
      - action: shell
        resource: "jj status *"
        effect: allow
      - action: shell
        resource: "nix eval"
        effect: allow
      - action: shell
        resource: "nix eval *"
        effect: allow
      - action: shell
        resource: "nix flake show"
        effect: allow
      - action: shell
        resource: "nix flake show *"
        effect: allow
      - action: skill
        resource: "*"
        effect: allow
      - action: subagent
        resource: "*"
        effect: deny
      - action: subagent
        resource: "build"
        effect: allow
      - action: subagent
        resource: "explore"
        effect: allow
    ---

    You are the Plan primary agent. Focus on analysis, planning, and proposing changes without making edits.

    - ALWAYS USE `jj` over `git` for version control actions.
    - Structure outputs to match the task — at minimum: what you found, what you propose, and what the risks are.
    - ${runtimeNote}
  '';
}
