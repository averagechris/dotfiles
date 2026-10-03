use std::fs;
use std::path::Path;
use std::process::Command;

/// Probe strict CoW support using a nonempty fixture on the test filesystem.
/// The caller provides a unique root to keep parallel test probes isolated.
pub fn strict_cow_clone_supported(root: &Path) -> bool {
    let probe = root.join("cow-probe");
    let src = probe.join("source");
    let dest = probe.join("destination");
    fs::create_dir_all(&src).unwrap();
    fs::write(src.join("marker.txt"), "nonempty clone fixture\n").unwrap();

    let (program, args): (&str, &[&str]) = if cfg!(target_os = "macos") {
        ("/bin/cp", &["-cR"])
    } else {
        ("cp", &["-a", "--reflink=always"])
    };
    let output = Command::new(program)
        .args(args)
        .env("LC_ALL", "C")
        .arg(&src)
        .arg(&dest)
        .output()
        .unwrap_or_else(|error| panic!("failed to run {program} CoW capability probe: {error}"));

    let supported = if output.status.success() {
        assert_eq!(
            fs::read_to_string(dest.join("marker.txt")).unwrap(),
            "nonempty clone fixture\n",
            "successful CoW probe must clone the nonempty marker"
        );
        true
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr).to_ascii_lowercase();
        let reports_clone_failure = stderr.contains("clone") || stderr.contains("reflink");
        let reports_unsupported = [
            "operation not supported",
            "function not implemented",
            "invalid cross-device link",
            "inappropriate ioctl for device",
        ]
        .iter()
        .any(|message| stderr.contains(message));
        assert!(
            reports_clone_failure && reports_unsupported,
            "unexpected CoW capability probe failure (status {}): {}",
            output.status,
            stderr.trim()
        );
        false
    };

    let _ = fs::remove_dir_all(&probe);
    supported
}
