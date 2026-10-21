{pkgs}: let
  inherit (pkgs) lib;
  howDirectory = ../opencode/skills/how;
  whyDirectory = ../opencode/skills/why;
  # Fail on source drift instead of silently retaining obsolete client guidance.
  replaceChecked = from: to: text:
    assert lib.all (fragment: lib.hasInfix fragment text) from;
      builtins.replaceStrings from to text;
  howText =
    replaceChecked [
      "When breadth or residual uncertainty makes delegation worthwhile, load `subagent-selection` and use focused Explore agents. Split only distinct research angles that can run independently. For example, a broad rate-limiter question might separate state management, request enforcement, and configuration or metrics."
      "Apply the [architectural critique rubric](references/architectural-critique-rubric.md) to the actual code. When an independent view would add signal, load `subagent-selection` and use one focused reviewer with the [critic prompt template](references/critic-prompt-template.md). Give it the explanation, relevant paths, and rubric. A reviewer is optional, not a panel."
    ] [
      "When independent research would help and delegation is available, split distinct questions across focused Codex subagents according to the routing guidance in AGENTS.md. For example, a broad rate-limiter question might separate state management, request enforcement, and configuration or metrics."
      "Apply the [architectural critique rubric](references/architectural-critique-rubric.md) to the actual code. When an independent view would add signal and delegation is available, ask one focused Codex subagent for a review according to the routing guidance in AGENTS.md. Give it the explanation, relevant paths, and rubric. A reviewer is optional, not a panel."
    ] (builtins.readFile (howDirectory + "/SKILL.md"));
  whyText =
    replaceChecked [
      "load `subagent-selection` and assign focused, non-overlapping sources or questions. Each investigator stays read-only and receives:"
      "load `subagent-selection` and give one read-only synthesizer:"
      "Use agent history only after normal searches or to recover missing links, and verify its leads against a first-class source."
    ] [
      "when delegation is available, assign focused, non-overlapping research to Codex subagents according to the routing guidance in AGENTS.md. Each investigator stays read-only and receives:"
      "when delegation is available, assign one read-only Codex subagent as synthesizer according to the routing guidance in AGENTS.md:"
      "Use available session history only after normal searches or to recover missing links, and verify its leads against a first-class source."
    ] (builtins.readFile (whyDirectory + "/SKILL.md"));
  investigatorText =
    replaceChecked [
      "Use only available OpenCode tools, skills, CLIs, and integrations."
      "7. Treat `ctx` results only as leads. Verify them against a source in the assigned category before reporting a claim."
    ] [
      "Use only available tools, skills, CLIs, and integrations."
      "7. Treat session-history results only as leads. Verify them against a source in the assigned category before reporting a claim."
    ] (builtins.readFile (whyDirectory + "/references/investigator-prompt-template.md"));
  synthesizerText =
    replaceChecked [
      "7. Exclude agent-history conclusions unless an authoritative source verifies the claim. Keep unverified `ctx` results as leads or gaps."
    ] [
      "7. Exclude agent-history conclusions unless an authoritative source verifies the claim. Keep unverified session-history results as leads or gaps."
    ] (builtins.readFile (whyDirectory + "/references/synthesizer-prompt-template.md"));
  explorerText =
    replaceChecked [
      "Use Glob to find directories and files, Grep to find key symbols, Read to understand the actual implementation."
    ] [
      "Use available file and search tools to find directories and symbols, then read the actual implementation."
    ] (builtins.readFile (howDirectory + "/references/explorer-prompt-template.md"));
  historyText =
    replaceChecked [
      "Use `ctx` only as a cross-cutting lead source."
      "A null search is limited by what `ctx` indexed and retained"
    ] [
      "Use available session-history search only as a cross-cutting lead source."
      "A null search is limited by what the available history search indexed and retained"
    ] (builtins.readFile (whyDirectory + "/references/sources/agent-history.md"));
in {
  how = pkgs.runCommand "codex-how-source" {} ''
    cp -R ${howDirectory} "$out"
    chmod -R u+w "$out"
    cp ${pkgs.writeText "codex-how-SKILL.md" howText} "$out/SKILL.md"
    cp ${pkgs.writeText "codex-how-explorer-prompt.md" explorerText} "$out/references/explorer-prompt-template.md"
  '';
  why = pkgs.runCommand "codex-why-source" {} ''
    cp -R ${whyDirectory} "$out"
    chmod -R u+w "$out"
    cp ${pkgs.writeText "codex-why-SKILL.md" whyText} "$out/SKILL.md"
    cp ${pkgs.writeText "codex-why-investigator-prompt.md" investigatorText} "$out/references/investigator-prompt-template.md"
    cp ${pkgs.writeText "codex-why-synthesizer-prompt.md" synthesizerText} "$out/references/synthesizer-prompt-template.md"
    cp ${pkgs.writeText "codex-why-agent-history.md" historyText} "$out/references/sources/agent-history.md"
  '';
}
