# Helix editor

Home Manager module: `flakes/hm-modules/modules/helix/default.nix`.

The module installs Helix with a curated tree-sitter runtime instead of the full
upstream grammar set. This keeps daily language support while avoiding hundreds
of rarely used grammar outputs in host closures.

The module passes `grammarPackageNames` to Helix's `includeGrammarIf` package
option. Helix filters its grammar definitions before it fetches or builds their
sources, so unselected grammars do not become evaluation-time fetches or build
dependencies. The module then copies those same named grammar libraries into a
curated runtime and makes `hx` use it through `HELIX_RUNTIME`. Runtime assembly
fails if any configured grammar is missing rather than silently dropping it.

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

Grammar names match files in Helix's runtime `grammars/` directory without the
platform shared-library suffix, for example `typescript` for
`typescript.dylib`/`typescript.so`.
