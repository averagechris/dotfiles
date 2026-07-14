{runtimeNote}: let
  deletionBashPermissions = {allowAbsoluteTempCleanup ? false}:
    builtins.concatStringsSep "\n    " (
      [
        "# Normal relative cleanup is allowed; broad or sensitive deletion targets"
        "# are interrupted. These command globs are guardrails, not a shell sandbox."
        ''"rm -rf /": "deny"''
        ''"rm -rf /*": "deny"''
      ]
      ++ (
        if allowAbsoluteTempCleanup
        then [
          "# OpenCode already limits these external paths to trusted temp"
          "# namespaces. Permit the common absolute cleanup form as well."
          ''"rm -rf /tmp/*": "allow"''
          ''"rm -rf /private/tmp/*": "allow"''
          ''"rm -rf /var/folders/*/T/opencode/*": "allow"''
          ''"rm -rf /private/var/folders/*/T/opencode/*": "allow"''
        ]
        else []
      )
      ++ [
        ''"rm -rf .": "ask"''
        ''"rm -rf .*": "ask"''
        ''"rm -rf ~*": "ask"''
        ''"rm -rf $HOME*": "ask"''
        ''"rm -rf /Users*": "ask"''
        ''"rm -rf *secrets*": "ask"''
        ''"rm -r *secrets*": "ask"''
        ''"rm *secrets*": "ask"''
      ]
    );
in {
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
        # Rules are evaluated in insertion order with the last match winning.
        # Default the build agent to open execution, then put sharp edges behind
        # an approval prompt so rare denies are easier to notice.
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
      skill:
        "*": "allow"
      task:
        "*": "deny"
        "build": "allow"
        "coding-minion": "allow"
        "explore": "allow"
    ---

    You are the Build primary agent. Use this agent for full development and code change workflows.
    ALWAYS USE `jj` over `git` for version control actions.
    ${runtimeNote}
  '';

  orchestrator = ''
    ---
    description: Orchestrator agent - ambitious multi-track development workflows. Use when a project benefits from planning, parallel work, and delegated coding tasks.
    mode: all
    temperature: 0.0
    steps: 160
    permission:
      read: "allow"
      edit: "allow"
      glob: "allow"
      grep: "allow"
      list: "allow"
      webfetch: "allow"
      bash:
        # Rules are evaluated in insertion order with the last match winning.
        # Default the orchestrator agent to open execution, then put sharp edges
        # behind an approval prompt so rare denies are easier to notice.
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
      skill:
        "*": "allow"
      task:
        "*": "deny"
        "build": "allow"
        "coding-minion": "allow"
        "explore": "allow"
    ---

    You are the Orchestrator primary agent. Use this agent for ambitious development projects that benefit from planning, parallel execution, and delegated implementation.
    ALWAYS USE `jj` over `git` for version control actions.
    ${runtimeNote}

    Orchestration workflow:

    - Start by clarifying the goal, constraints, and verification target, then keep a live task list with `todowrite`.
    - Decompose large work into independent tracks with clear ownership, inputs, expected outputs, and validation commands.
    - Prefer delegating coding tasks to the `coding-minion` subagent whenever a track is reasonably self-contained. Use `explore` for focused codebase research and only keep implementation work yourself when it is tightly coupled, high-risk, or needed to integrate delegated results.
    - Launch independent minion tasks in parallel when their file areas or responsibilities do not conflict. Give each minion a precise prompt that includes the task boundary, acceptance criteria, verification command, and how to report changed files, test results, blockers, and cleanup status.
    - For parallel coding work, instruct each minion to use an isolated managed jj workspace: create a short unique name, run `jj ws add <name> -q` (or `jj ws add <name> -r @ -q` when it must start from your current working copy), do all work from that workspace path, and report the workspace name/path back.
    - Instruct minions to clean up scratch workspaces with `jj ws forget <name>` when they did not leave deliverable changes. When they do leave changes, they should keep the workspace until you have inspected/integrated or explicitly abandoned the work; then run `jj ws forget <name>` (use `--dry-run` first when safety is unclear).
    - After minions finish, inspect their reported diffs and verification output yourself, resolve conflicts or integration issues, run the final validation from the integration workspace, and summarize what landed plus any remaining workspace cleanup.
  '';

  coding-minion = ''
    ---
    description: Coding Minion subagent - fast, cheap development delegation for routine coding tasks. Use when primary orchestrator agents want a solid lower-cost coder that is a bit less smart than the primary Build agent.
    mode: subagent
    model: openrouter/openai/gpt-5.5
    variant: low
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
        # Rules are evaluated in insertion order with the last match winning.
        # Default the build agent to open execution, then put sharp edges behind
        # an approval prompt so rare denies are easier to notice.
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
      skill:
        "*": "allow"
      task:
        "*": "deny"
        "build": "allow"
        "coding-minion": "allow"
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
