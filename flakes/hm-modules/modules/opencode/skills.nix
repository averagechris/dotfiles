let
  skillDirectory = name: ./skills/${name};
  skill = name: builtins.readFile (skillDirectory name + "/SKILL.md");
  agentSelectionPolicy = builtins.readFile ./agent-selection-policy.md;
  agentSelectionTable = builtins.readFile ./agent-selection-table.md;
in {
  jj-vcs = skillDirectory "jj-vcs";
  jj-change-management = skillDirectory "jj-change-management";
  jj-conflict-resolution = skillDirectory "jj-conflict-resolution";
  jj-repo-workflow = skillDirectory "jj-repo-workflow";
  jj-workspaces = skillDirectory "jj-workspaces";
  conventional-commits = skillDirectory "conventional-commits";
  code-review = skillDirectory "code-review";
  databricks-cli = skillDirectory "databricks-cli";
  # adapted from https://github.com/cursor/plugins/tree/fd6dd6f7276956a532bb78a748a8d2818b6eb5f4/pstack/skills/how
  how = skillDirectory "how";
  # adapted from https://github.com/cursor/plugins/tree/fd6dd6f7276956a532bb78a748a8d2818b6eb5f4/pstack/skills/why
  why = skillDirectory "why";
  # adapted from https://github.com/cursor/plugins/tree/46125561306434d8a1d7745d540d8932ab0cd2a2/pstack/skills/interrogate
  interrogate-me = skillDirectory "interrogate-me";
  linear-cli = skillDirectory "linear-cli";
  subagent-selection = ''
    ${skill "subagent-selection"}
    ${agentSelectionPolicy}
    ${agentSelectionTable}
  '';

  # based on https://github.com/cursor/plugins/blob/fd6dd6f7276956a532bb78a748a8d2818b6eb5f4/pstack/skills/unslop/SKILL.md
  impactful-writing = skillDirectory "impactful-writing";
}
