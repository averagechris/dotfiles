{
  lib,
  pkgs,
  ...
}: let
  iniFormat = pkgs.formats.ini {};
  awscliConfig = {
    sso_start_url = "https://sureplatform.awsapps.com/start";
    sso_region = "us-east-1";
    region = "us-east-1";
    output = "json";
  };

  refresh-poetry-auth = pkgs.writeShellScriptBin "refresh-poetry-auth" ''
    set -euo pipefail

    echo "Refreshing poetry auth token for CodeArtifact..."

    # Login to AWS SSO
    aws sso login --profile registries-read

    # Get auth token and configure poetry
    poetry config http-basic.codeartifact aws "$(aws codeartifact get-authorization-token \
      --profile registries-read \
      --domain sure \
      --query authorizationToken \
      --output text \
      --duration-seconds 0)"

    echo "Poetry auth token refreshed successfully"
  '';

  # Non-production EKS clusters whose aws-auth maps the SSO role directly, so
  # kubectl can use `aws eks get-token` without a StrongDM hop (production still
  # goes through `sdm kubernetes update-config`, which writes ~/.kube/config).
  # The rendered kubeconfig is kept encrypted in secrets/suremac-kubeconfig-eks.age
  # and merged via KUBECONFIG below. To add or refresh a cluster: edit this
  # list, then `render-eks-kubeconfig | agenix -e secrets/suremac-kubeconfig-eks.age`
  # (agenix reads stdin when it is not a TTY) and switch.
  eksClusters = [
    {
      profile = "connect-qa";
      cluster = "sure-qa-k8s-use1";
    }
    {
      profile = "connect-qa";
      cluster = "connect-qa-k8s-use1";
    }
    {
      profile = "connect-sandbox";
      cluster = "sure-sandbox-k8s-use1";
    }
    {
      profile = "connect-sandbox";
      cluster = "connect-sandbox-k8s-use1";
    }
    {
      profile = "qa";
      cluster = "surecraft-qa-k8s-useast1";
      context = "qa-useast1";
    }
    {
      profile = "sandbox";
      cluster = "surecraft-sandbox-k8s-useast1";
      context = "sandbox-use1";
    }
  ];
  eksClusterSpecs = builtins.concatStringsSep " " (map (
      c: "${c.profile}:${c.cluster}:${c.context or c.cluster}"
    )
    eksClusters);

  render-eks-kubeconfig = pkgs.writeShellScriptBin "render-eks-kubeconfig" ''
    set -euo pipefail
    export PATH=${pkgs.lib.makeBinPath [pkgs.jq]}:$PATH

    entries='[]'
    for spec in ${eksClusterSpecs}; do
      IFS=: read -r profile cluster context <<<"$spec"
      echo "describing $cluster via profile $profile" >&2
      described=$(aws --profile "$profile" --region us-east-1 eks describe-cluster --name "$cluster" --output json)
      entries=$(jq -c --arg profile "$profile" --arg cluster "$cluster" --arg context "$context" \
        '. + [{profile: $profile, cluster: $cluster, context: $context,
               server: $ARGS.named.described.cluster.endpoint,
               ca: $ARGS.named.described.cluster.certificateAuthority.data}]' \
        --argjson described "$described" <<<"$entries")
    done

    jq '{
      apiVersion: "v1", kind: "Config", preferences: {},
      clusters: map({name: .context, cluster: {server, "certificate-authority-data": .ca}}),
      users: map({name: .context, user: {exec: {
        apiVersion: "client.authentication.k8s.io/v1beta1", command: "aws",
        args: ["--profile", .profile, "--region", "us-east-1", "eks", "get-token", "--cluster-name", .cluster, "--output", "json"],
        interactiveMode: "IfAvailable", provideClusterInfo: false}}}),
      contexts: map({name: .context, context: {cluster: .context, user: .context, namespace: "default"}})
    }' <<<"$entries"
  '';

  install-sure-tools = pkgs.writeShellScriptBin "install-sure-tools" ''
    set -euo pipefail

    # Private sureapp flakes installed imperatively via `nix profile` because
    # they require GitHub auth at fetch time and update on their own cadence.
    # Capture the profile list up front: piping straight into `grep -q` can
    # die with SIGPIPE under pipefail once the output outgrows the pipe buffer.
    profile_list=$(nix profile list)
    failed=0
    for tool in surecraft-cli suremise; do
      if grep -qF "github:sureapp/$tool" <<<"$profile_list"; then
        echo "Upgrading $tool in the nix profile..."
        nix profile upgrade "$tool" || {
          echo "warning: failed to upgrade $tool (GitHub auth?)" >&2
          failed=1
        }
      else
        echo "Installing github:sureapp/$tool into the nix profile..."
        nix profile install "github:sureapp/$tool" || {
          echo "warning: failed to install $tool (GitHub auth?)" >&2
          failed=1
        }
      fi
    done

    nix profile list
    exit "$failed"
  '';
in {
  home.file.".aws/config".source = iniFormat.generate "awscli.config" {
    "profile qa" =
      awscliConfig
      // {
        sso_account_id = "312107431298";
        sso_role_name = "non-production-backend-access";
      };

    "profile sandbox" =
      awscliConfig
      // {
        sso_account_id = "312107431298";
        sso_role_name = "non-production-backend-access";
      };

    # Sure Connect (platform-connect / connect-app) non-production account.
    # Same SSO role name as the Surecraft profiles above, different account.
    "profile connect-qa" =
      awscliConfig
      // {
        sso_account_id = "186258024085";
        sso_role_name = "non-production-backend-access";
      };

    "profile connect-sandbox" =
      awscliConfig
      // {
        sso_account_id = "186258024085";
        sso_role_name = "non-production-backend-access";
      };

    "profile registries-read" =
      awscliConfig
      // {
        sso_account_id = "348777858795";
        sso_role_name = "RegistryReadAccess";
      };
  };

  home.packages = [refresh-poetry-auth install-sure-tools render-eks-kubeconfig];

  # kubectl creates a sibling .lock file when `config use-context` updates a
  # kubeconfig. The agenix output is intentionally read-only, so copy it to a
  # writable user-owned fragment before exposing it through KUBECONFIG.
  home.activation.syncSuremacKubeconfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    source=/run/agenix/suremac-kubeconfig-eks
    target="$HOME/.kube/suremac-kubeconfig-eks"
    if [[ -r "$source" ]]; then
      mkdir -p "$HOME/.kube"
      if [[ ! -r "$target" ]] || ! cmp -s "$source" "$target"; then
        cp "$source" "$target"
      fi
      chmod 600 "$target"
    else
      echo "warning: $source is not available; keeping any existing $target" >&2
    fi
  '';

  # NOTE: Launchd agents for auto-refresh removed due to poetry build issues in nixpkgs.
  # Run `refresh-poetry-auth` manually when needed.

  programs.zsh = {
    sessionVariables = {
      AWS_PROFILE = "qa";
      # ~/.kube/config stays writable for StrongDM; the copied agenix fragment
      # adds the SSO-reachable EKS contexts and supports `use-context` locks.
      KUBECONFIG = "$HOME/.kube/config:$HOME/.kube/suremac-kubeconfig-eks";
    };
  };
}
