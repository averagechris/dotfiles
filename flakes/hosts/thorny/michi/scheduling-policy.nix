{
  lib,
  kagiEnabled ? true,
}: let
  memoryTools = ["memo"];
  searchTools = lib.optional kagiEnabled "web_search_tool";
  schedulingTools = ["cron_add" "cron_list" "cron_update" "cron_remove" "cron_run" "cron_runs"];
  sharedTools = memoryTools ++ ["reaction" "image_gen"] ++ searchTools;
  allowedTools = sharedTools ++ schedulingTools;
  autoApprove = allowedTools;
in {
  inherit schedulingTools allowedTools autoApprove;

  settings = {
    scheduler.missed_run_policy = "review";

    agents.guest_template.risk_profile = "guests";
    agents.group_template.risk_profile = "guests";

    risk_profiles = {
      owner = {
        allowed_tools = allowedTools ++ ["shell"];
        auto_approve = autoApprove ++ ["shell"];
      };
      guests = {
        allowed_tools = sharedTools;
        excluded_tools = ["shell"];
        auto_approve = sharedTools;
      };
    };
  };
}
