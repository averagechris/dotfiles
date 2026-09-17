use crate::ws::ProjectGroup;
use std::path::Path;

#[derive(Debug, PartialEq, Eq)]
pub(crate) enum RouteError {
    NoGroup,
}

impl RouteError {
    pub(crate) fn exit_code(&self) -> i32 { 3 }
    pub(crate) fn kind(&self) -> &'static str { "no_group" }
}

/// Select a destination without doing repository or network I/O.
pub(crate) fn route_group<'a>(
    groups: &'a [ProjectGroup],
    explicit: Option<&Path>,
    owner: Option<&str>,
) -> Result<&'a ProjectGroup, RouteError> {
    if let Some(path) = explicit {
        return groups.iter().find(|group| group.path == path).ok_or(RouteError::NoGroup);
    }
    if let Some(owner) = owner {
        if let Some(group) = groups.iter().find(|group| {
            group.github_owners.iter().any(|candidate| candidate != "*" && candidate.eq_ignore_ascii_case(owner))
        }) {
            return Ok(group);
        }
    }
    groups.iter().find(|group| group.github_owners.iter().any(|owner| owner == "*")).ok_or(RouteError::NoGroup)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn group(path: &str, owners: &[&str]) -> ProjectGroup {
        ProjectGroup { path: PathBuf::from(path), workspace_dir: "ws".into(), github_owners: owners.iter().map(|s| (*s).into()).collect() }
    }

    #[test]
    fn exact_case_insensitive_match_beats_wildcard() {
        let groups = [group("/fallback", &["*"]), group("/work", &["SureApp"])];
        assert_eq!(route_group(&groups, None, Some("sureapp")).unwrap().path, PathBuf::from("/work"));
    }

    #[test]
    fn explicit_configured_group_overrides_owner() {
        let groups = [group("/personal", &["me"]), group("/work", &["sureapp"])];
        assert_eq!(route_group(&groups, Some(Path::new("/personal")), Some("sureapp")).unwrap().path, PathBuf::from("/personal"));
    }

    #[test]
    fn unmatched_owner_uses_wildcard_and_missing_wildcard_is_no_group() {
        let groups = [group("/personal", &["me"]), group("/fallback", &["*"])];
        assert_eq!(route_group(&groups, None, Some("other")).unwrap().path, PathBuf::from("/fallback"));
        assert!(matches!(route_group(&groups[..1], None, Some("other")), Err(RouteError::NoGroup)));
        assert_eq!(RouteError::NoGroup.exit_code(), 3);
        assert_eq!(RouteError::NoGroup.kind(), "no_group");
    }
}
