let
  skill = name: builtins.readFile ./skills/${name}/SKILL.md;
  agentSelectionTable = builtins.readFile ./agent-selection-table.md;
in {
  jj-vcs = skill "jj-vcs";
  jj-change-management = skill "jj-change-management";
  jj-conflict-resolution = skill "jj-conflict-resolution";
  jj-repo-workflow = skill "jj-repo-workflow";
  jj-workspaces = skill "jj-workspaces";
  conventional-commits = skill "conventional-commits";
  code-review = skill "code-review";
  databricks-cli = skill "databricks-cli";
  linear-cli = skill "linear-cli";
  subagent-selection = ''
    ${skill "subagent-selection"}
    ${agentSelectionTable}
  '';
}
