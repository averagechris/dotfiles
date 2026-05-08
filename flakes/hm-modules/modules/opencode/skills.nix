let
  skill = name: builtins.readFile ./skills/${name}/SKILL.md;
in {
  jj-vcs = skill "jj-vcs";
  jj-change-management = skill "jj-change-management";
  jj-conflict-resolution = skill "jj-conflict-resolution";
  jj-repo-workflow = skill "jj-repo-workflow";
  jj-workspaces = skill "jj-workspaces";
  conventional-commits = skill "conventional-commits";
  code-review = skill "code-review";
  changes-review-core = skill "changes-review-core";
  github-pr-review = skill "github-pr-review";
  databricks-cli = skill "databricks-cli";
  linear-cli = skill "linear-cli";
}
