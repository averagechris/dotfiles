{lib, ...}: let
  names = [
    "advisor-council"
    "conventional-commits"
    "test-curation"
    "teach"
    "project-map"
    "impactful-writing"
    "technical-writing"
    "rust-cargo"
  ];
in {
  imports = [./agent-skills.nix];
  dotfiles.agentSkills = lib.genAttrs names (name: {
    source = lib.mkDefault ./opencode/skills/${name};
    targets = lib.mkDefault ["opencode" "codex"];
  });
}
