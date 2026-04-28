let
  skill = name: builtins.readFile ./skills/${name}/SKILL.md;
in {
  jj-vcs = skill "jj-vcs";
  conventional-commits = skill "conventional-commits";
  code-review = skill "code-review";
  changes-review-core = skill "changes-review-core";
  github-pr-review = skill "github-pr-review";
  databricks-cli = skill "databricks-cli";
  linear-cli = skill "linear-cli";
}
