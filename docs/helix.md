# Helix editor

Home Manager module: `flakes/hm-modules/modules/helix/default.nix`.

The module installs the stable Helix package from the repository's pinned
nixpkgs, with a curated tree-sitter runtime. This keeps daily language support
while avoiding hundreds of rarely used grammar outputs in host closures.

The module uses `grammarPackageNames` to select nixpkgs' locked grammar sources
before its Helix wrapper builds the runtime. Unknown names fail evaluation.
An empty list installs the editor without parsers. The Helix 25.07.1 package
does not provide the `shellcheckrc` grammar.

Default grammar coverage focuses on:

- Rust, Python, Nix, Gleam, and shell scripts;
- TypeScript/JavaScript and common web formats/frameworks;
- Markdown, JSON, TOML, XML, SQL, and common config formats;
- cloud/devops files such as Dockerfile, YAML, HCL/Terraform-style syntax,
  CUE, Rego, nginx/Caddy configs, git configs, and SSH/hosts files.

Notably, the default set intentionally omits broad low-use language families and
C/C++ grammars. Add back specific grammars only when they are part of regular
work, not just because upstream Helix supports them.

Override or extend the list with:

```nix
programs.helix.grammarPackageNames = [
  "rust"
  "python"
  "nix"
  # ...
];
```

Use names from nixpkgs' `pkgs/by-name/he/helix/grammars.json`. The module also
accepts `markdown_inline` and `ssh_client_config`, which map to
`markdown-inline` and `sshclientconfig` in nixpkgs.
