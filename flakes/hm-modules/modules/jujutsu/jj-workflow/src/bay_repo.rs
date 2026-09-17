use crate::ws::ProjectGroup;
use std::path::Path;

/// Parse a GitHub repository identity from a slug or clone/browser URL.
/// Browser URL suffixes are deliberately ignored: repository identity is the
/// first two path components.
pub(crate) fn github_slug(value: &str) -> Option<(String, String)> {
    let value = value.trim();
    let (path, allow_suffix) = if let Some(path) = value.strip_prefix("git@github.com:") {
        (path, false)
    } else if let Some(path) = value.strip_prefix("ssh://git@github.com/") {
        (path, false)
    } else if value.get(..8).is_some_and(|scheme|scheme.eq_ignore_ascii_case("https://")) {
        let rest=&value[8..];
        let (host,path)=rest.split_once('/')?;
        if !host.eq_ignore_ascii_case("github.com") { return None; }
        (path.split(['?','#']).next()?, true)
    } else if value.contains("://") || value.contains('@') {
        return None;
    } else {
        (value, false)
    };
    let mut parts = path.split('/');
    let owner = parts.next()?;
    let raw_repo = parts.next()?;
    let repo = raw_repo.strip_suffix(".git").unwrap_or(raw_repo);
    if !allow_suffix && parts.next().is_some() { return None; }
    let valid = |s: &str| !s.is_empty() && s != "." && s != ".." && s.bytes().all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.'));
    if !valid(owner) || !valid(repo) { return None; }
    Some((owner.to_string(), repo.to_string()))
}

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

    #[test]
    fn github_identity_parser_table() {
        for (input, expected) in [
            ("SureApp/api", Some(("SureApp", "api"))),
            ("SureApp/api.git", Some(("SureApp", "api"))),
            ("https://github.com/SureApp/api/pull/42", Some(("SureApp", "api"))),
            ("https://github.com/SureApp/api/tree/main/src", Some(("SureApp", "api"))),
            ("HTTPS://GITHUB.COM/SureApp/api?tab=readme#top", Some(("SureApp", "api"))),
            ("https://github.com/SureApp/api.git?x=1", Some(("SureApp", "api"))),
            ("https://github.com.evil/SureApp/api", None),
            ("git@github.com:SureApp/api.git", Some(("SureApp", "api"))),
            ("ssh://git@github.com/SureApp/api.git", Some(("SureApp", "api"))),
            ("api", None),
            ("https://gitlab.com/SureApp/api", None),
            ("SureApp/", None),
            ("/api", None),
        ] {
            assert_eq!(github_slug(input), expected.map(|(o,n)|(o.into(),n.into())), "{input}");
        }
    }
}
