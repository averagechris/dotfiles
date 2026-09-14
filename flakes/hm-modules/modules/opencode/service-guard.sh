# shellcheck shell=bash
require_running_opencode_service() {
  service_status=$(opencode service status 2>/dev/null) || return 75
  case "$service_status" in
    http://*|https://*) return 0 ;;
    *) return 75 ;;
  esac
}
