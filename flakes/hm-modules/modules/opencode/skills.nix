let
  skillDirectory = name: ./skills/${name};
  skill = name: builtins.readFile (skillDirectory name + "/SKILL.md");
  agentSelectionPolicy = builtins.readFile ./agent-selection-policy.md;
  agentSelectionTable = builtins.readFile ./agent-selection-table.md;
in {
  jj-change-management = skillDirectory "jj-change-management";
  jj-conflict-resolution = skillDirectory "jj-conflict-resolution";
  jj-repo-workflow = skillDirectory "jj-repo-workflow";
  bay-workspaces = skillDirectory "bay-workspaces";
  conventional-commits = skillDirectory "conventional-commits";
  code-review = skillDirectory "code-review";
  test-curation = skillDirectory "test-curation";
  # adapted from https://github.com/cursor/plugins/tree/fd6dd6f7276956a532bb78a748a8d2818b6eb5f4/pstack/skills/how
  how = skillDirectory "how";
  # adapted from https://github.com/cursor/plugins/tree/fd6dd6f7276956a532bb78a748a8d2818b6eb5f4/pstack/skills/why
  why = skillDirectory "why";
  # adapted from https://github.com/cursor/plugins/tree/46125561306434d8a1d7745d540d8932ab0cd2a2/pstack/skills/interrogate
  interrogate-me = skillDirectory "interrogate-me";
  # adapted from https://github.com/cursor/plugins/tree/46125561306434d8a1d7745d540d8932ab0cd2a2/pstack/skills/teach
  teach = skillDirectory "teach";
  # adapted from https://github.com/cursor/plugins/tree/46125561306434d8a1d7745d540d8932ab0cd2a2/pstack/skills/recall
  recall = skillDirectory "recall";
  # adapted from https://github.com/cursor/plugins/tree/46125561306434d8a1d7745d540d8932ab0cd2a2/pstack/skills/reflect
  reflect = skillDirectory "reflect";
  # adapted from https://github.com/cursor/plugins/tree/46125561306434d8a1d7745d540d8932ab0cd2a2/pstack/skills/blast-radius
  blast-radius = skillDirectory "blast-radius";
  # adapted from https://github.com/cursor/plugins/tree/46125561306434d8a1d7745d540d8932ab0cd2a2/pstack/skills/architect
  architect = skillDirectory "architect";
  # adapted from https://github.com/mattpocock/skills/blob/5b15a47f2d7150f545fbcacbfe381787fc0230dc/skills/engineering/wayfinder/SKILL.md
  project-map = skillDirectory "project-map";
  subagent-selection = ''
    ${skill "subagent-selection"}
    ${agentSelectionPolicy}
    ${agentSelectionTable}
  '';

  # based on https://github.com/cursor/plugins/blob/fd6dd6f7276956a532bb78a748a8d2818b6eb5f4/pstack/skills/unslop/SKILL.md
  impactful-writing = skillDirectory "impactful-writing";
  # adapted from https://github.com/cursor/plugins/blob/46125561306434d8a1d7745d540d8932ab0cd2a2/pstack/skills/technical-writing/SKILL.md
  technical-writing = skillDirectory "technical-writing";
}
