{
  description = "Suremac Darwin system configuration";

  inputs = {
    base-lib.url = "path:../../base-lib";
    nixpkgs.follows = "base-lib/nixpkgs";
    hm-modules = {
      url = "path:../../hm-modules";
      inputs.base-lib.follows = "base-lib";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.home-manager.follows = "home-manager";
      inputs.opencode.follows = "base-lib/opencode";
      inputs.nitter-link.follows = "nitter-link";
      inputs.fleet.follows = "fleet";
      inputs.srht.follows = "srht";
    };
    darwin-modules = {
      url = "path:../../darwin-modules";
      inputs.base-lib.follows = "base-lib";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.home-manager.follows = "home-manager";
      inputs.darwin.follows = "darwin";
    };
    darwin.follows = "base-lib/darwin";
    home-manager.follows = "base-lib/home-manager";
    flake-utils.follows = "base-lib/flake-utils";
    agenix.follows = "base-lib/agenix";
    deploy-rs.follows = "base-lib/deploy-rs";
    titlecase.follows = "base-lib/titlecase";
    helix = {
      # Don't follow nixpkgs - use helix's own nixpkgs to get cached builds
      # from helix.cachix.org (avoids building Swift/dotnet for tree-sitter grammars)
      url = "github:helix-editor/helix";
    };
    starship-jj.follows = "hm-modules/starship-jj";
    linear-cli.follows = "hm-modules/linear-cli";
    gander.follows = "hm-modules/gander";
    fleet = {
      url = "github:averagechris/averagechris.github.io";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.srht.follows = "srht";
    };
    srht = {
      url = "github:averagechris/srht";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.follows = "fleet";
    };
    granola-cli = {
      url = "github:averagechris/granola-cli";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.fleet.follows = "fleet";
    };
    sideshow = {
      url = "github:averagechris/sideshow";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.follows = "fleet";
    };
    rdny = {
      url = "github:averagechris/rdny";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.follows = "fleet";
    };
    slack = {
      url = "github:averagechris/slack";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.fleet.follows = "fleet";
    };
    ctx = {
      url = "github:averagechris/ctx";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.fleet.follows = "fleet";
    };
    nitter-link = {
      url = "github:averagechris/nitter-link/v0.1.4";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
      inputs.fleet.follows = "fleet";
    };
    t3-code-nix = {
      url = "github:averagechris/t3-code-nix/opencode-v2-pin";
      inputs.home-manager.follows = "home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    memo = {
      url = "github:averagechris/memo";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    base-lib,
    ...
  }: let
    inherit (base-lib) lib;
    system = "aarch64-darwin";
    pkgs = inputs.nixpkgs.legacyPackages.${system};
  in {
    darwinConfigurations.suremac = lib.mkDarwinHost {
      hostPath = ./configuration.nix;
      extraInputs = inputs;
    };

    checks.${system} = {
      opencode-jj-skills =
        pkgs.runCommand "opencode-jj-skills" {
          nativeBuildInputs = [
            (pkgs.python3.withPackages (python: [python.pyyaml]))
          ];
          skillRoot = inputs.hm-modules.outPath;
          checkScript = "${inputs.hm-modules.outPath}/modules/opencode/tests/check-jj-skills.py";
          suremacConfig = ./configuration.nix;
        } ''
          python3 "$checkScript" "$skillRoot" "$suremacConfig"
          if python3 "$checkScript" ${inputs.hm-modules.outPath}/tests/agent-skills/malformed; then
            echo "malformed skill YAML unexpectedly passed" >&2
            exit 1
          fi
          mkdir -p "$out"
        '';

      opencode-deployed-skills = let
        files = self.darwinConfigurations.suremac.config.home-manager.users.chris.xdg.configFile;
        skillFiles = pkgs.lib.filterAttrs (name: _: pkgs.lib.hasPrefix "opencode/skills/" name) files;
        manifest = pkgs.writeText "opencode-deployed-skills.json" (builtins.toJSON (map (destination: {
          inherit destination;
          source = toString skillFiles.${destination}.source;
        }) (builtins.attrNames skillFiles)));
      in
        pkgs.runCommand "opencode-deployed-skills" {
          nativeBuildInputs = [(pkgs.python3.withPackages (python: [python.pyyaml]))];
        } ''
          python3 ${inputs.hm-modules.outPath}/modules/opencode/tests/check-deployed-skills.py ${manifest}
          mkdir -p "$out"
        '';

      opencode-bay-plugin-loader = let
        homeConfig = self.darwinConfigurations.suremac.config.home-manager.users.chris;
        plugin = homeConfig.xdg.configFile."opencode/plugins/dotfiles-bay-worktrees.js".source;
        opencode = pkgs.lib.getExe homeConfig.programs.opencode.package;
        bay = "${homeConfig.dotfiles.jujutsu.workflowPackage}/bin/bay";
        deniedPackageManager = pkgs.writeShellScript "deny-opencode-package-manager" ''
          touch "$PACKAGE_MANAGER_MARKER"
          exit 99
        '';
      in
        pkgs.runCommand "opencode-bay-plugin-loader" {} ''
          mkdir -p home/.config/opencode/plugins home/.config/bay projects/demo fake-bin
          cp ${plugin} home/.config/opencode/plugins/dotfiles-bay-worktrees.js
          cat > home/.config/bay/config.toml <<EOF
          schema = 1
          [[groups]]
          path = "$PWD/projects"
          workspaces = "ws"
          EOF
          HOME="$PWD/home" ${pkgs.jujutsu}/bin/jj git init projects/demo
          repo="$PWD/projects/demo"
          HOME="$PWD/home" XDG_CONFIG_HOME="$PWD/home/.config" ${bay} list "$repo" --json > bay-list.json
          ${pkgs.jq}/bin/jq -e --arg repo "$repo" \
            'any(.workspaces[]; .path == $repo and .kind == "main")' bay-list.json
          for command in bun npm npx pnpm yarn; do
            ln -s ${deniedPackageManager} "fake-bin/$command"
          done
          ${pkgs.coreutils}/bin/env \
            HOME="$PWD/home" \
            XDG_CONFIG_HOME="$PWD/home/.config" \
            PATH="$PWD/fake-bin:${pkgs.coreutils}/bin" \
            PACKAGE_MANAGER_MARKER="$PWD/package-manager-attempted" \
            HTTPS_PROXY=http://127.0.0.1:9 \
            HTTP_PROXY=http://127.0.0.1:9 \
            NO_PROXY=127.0.0.1 \
            OPENCODE_PASSWORD=loader-test \
            OPENCODE_DISABLE_AUTOUPDATE=1 \
            ${opencode} --print-logs --log-level debug serve --hostname 127.0.0.1 --port 4099 \
            > server.txt 2> loader.log &
          pid=$!
          loaded=false
          for attempt in $(seq 1 50); do
            if ${pkgs.curl}/bin/curl --fail --silent --get \
              --user opencode:loader-test \
              --data-urlencode "location[directory]=$repo" \
              http://127.0.0.1:4099/api/config > config-sources.json; then
              loaded=true
              break
            fi
            ${pkgs.coreutils}/bin/sleep 0.1
          done
          ${pkgs.coreutils}/bin/sleep 1
          ${pkgs.curl}/bin/curl --fail --silent \
            --user opencode:loader-test --request POST \
            "http://127.0.0.1:4099/api/worktree/refresh?location%5Bdirectory%5D=$repo"
          ${pkgs.curl}/bin/curl --silent --get \
            --user opencode:loader-test \
            --data-urlencode "location[directory]=$repo" \
            http://127.0.0.1:4099/api/worktree > worktrees.json
          ${pkgs.curl}/bin/curl --silent \
            --user opencode:loader-test \
            --header 'content-type: application/json' \
            --request POST \
            --data "$( ${pkgs.jq}/bin/jq -nc \
              --arg directory "$PWD/requested" --arg from "$repo" \
              '{strategy:"bay", name:"loader-check", $directory, $from}' )" \
            --output created.json --write-out '%{http_code}' \
            "http://127.0.0.1:4099/api/worktree?location%5Bdirectory%5D=$repo" > created.status
          # The fresh project has not yet persisted a source row, but selecting
          # `bay` reaches source validation only if plugin setup registered that
          # strategy through ctx.worktree.transform(...).
          test "$(cat created.status)" = 400
          ${pkgs.jq}/bin/jq -e --arg repo "$repo" \
            '.name == "WorktreeError" and .data.message == ("Worktree source not found: " + $repo)' created.json
          ${pkgs.coreutils}/bin/sleep 0.5
          if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" || true
            wait "$pid" || true
          else
            wait "$pid" || status=$?
          fi
          test "$loaded" = true
          ${pkgs.gnugrep}/bin/grep -F 'loading plugin' loader.log
          ${pkgs.gnugrep}/bin/grep -F 'dotfiles-bay-worktrees.js' loader.log
          test ! -e package-manager-attempted
          test ! -e home/.config/opencode/package.json
          test ! -e home/.config/opencode/package-lock.json
          test ! -e home/.config/opencode/node_modules
          mkdir -p "$out"
        '';
    };
  };
}
