import { tool } from "@opencode-ai/plugin"

export default tool({
  description: "Create a representative GitHub review artifact for a PR and return it for renderer testing",
  args: {},
  async execute() {
    const artifact = {
      version: 1,
      source: {
        kind: "github_pr",
        title: "fix(sso): decouple IdP routing scope from provider cluster [EPD-4829]",
        url: "https://github.com/sureapp/surelock/pull/1304",
        repository: "sureapp/surelock",
        owner: "sureapp",
        repo: "surelock",
        prNumber: 1304,
        baseRef: "main",
        headRef: "chris/EPD-4829/sso-routing-scope",
        baseSha: "90ed724f",
        headSha: "f2d1100cbe87118bdd824acbf87b60a40492b0b7",
      },
      intentSummary:
        "Decouple SSO routing scope from the IdP provider cluster, preserve migrated sure_admin any-shard behavior under guardrails, and harden validation plus API/test coverage around routed token minting.",
      overallAssessment:
        "The change is directionally good and the test coverage is substantial, but the highest-risk review attention belongs on the SSO callback routing logic, create/update validation paths for routing_scope, migration semantics for legacy sure_admin IdPs, and API/schema behavior around nullable routing_scope. I would lean comment until the remaining questions are resolved, not auto-approve.",
      recommendedDisposition: "comment",
      findings: [
        {
          id: "routing-scope-null-openapi",
          severity: "non_blocking",
          scope: "cross_file",
          concernArea: "api",
          target: "summary_candidate",
          summary:
            "OpenAPI still advertises routing_scope as nullable even though the endpoint validators reject explicit null.",
          rationale:
            "The endpoint layer now raises validation errors for explicit null on create/update, but the schema snapshot shows routing_scope as anyOf[IdentityProviderRoutingScope, null]. That leaves a misleading contract for clients and can create avoidable API churn.",
          suggestedChange:
            "Make the schema match runtime behavior, or explicitly decide that null remains part of the public contract and change validation accordingly.",
          recommendationImpact: "comment",
          locations: [
            {
              file: "openapischema.json",
              startLine: 4085,
              endLine: 4097,
            },
            {
              file: "surelock/endpoints/sso.py",
              startLine: 60,
              endLine: 75,
            },
          ],
        },
        {
          id: "callback-admin-cluster-widening",
          severity: "non_blocking",
          scope: "architectural",
          concernArea: "authz",
          target: "summary_candidate",
          summary:
            "The sure_admin cluster widening rule is now an SSO-specific special case; worth calling out clearly as an intentional authz boundary decision.",
          rationale:
            "The new _coerce_routing_cluster_into_scoped_claims helper is probably the right place for this behavior, but it is a meaningful authorization exception. This is exactly the kind of rule that can become surprising later if the invariants are not crisp in docs/tests.",
          suggestedChange:
            "Make the security/ADR wording explicit that this widening is allowed only after IdP routing-scope validation and only for sure_admin in SSO-issued sessions.",
          recommendationImpact: "comment",
          locations: [
            {
              file: "surelock/domain/sso.py",
              startLine: 224,
              endLine: 258,
              symbol: "_coerce_routing_cluster_into_scoped_claims",
            },
            {
              file: "surelock/domain/sso.py",
              startLine: 973,
              endLine: 983,
            },
          ],
        },
        {
          id: "typed-update-kwargs-cleanup",
          severity: "nit",
          scope: "local",
          concernArea: "code_quality",
          target: "inline_candidate",
          summary:
            "The update kwargs assembly is clearer now, but this still reads like endpoint-layer defensive plumbing rather than a reusable request-mapping helper.",
          rationale:
            "Not a blocker, but this code will keep growing if more optional fields land. Pulling the body->kwargs mapping into a helper would make the endpoint easier to scan.",
          suggestedChange:
            "Consider extracting the PATCH body mapping into a tiny helper once this stabilizes.",
          recommendationImpact: "none",
          excerptHint: "update_kwargs: UpdateIdentityProviderKwargs = { ... }",
          locations: [
            {
              file: "surelock/endpoints/sso.py",
              startLine: 238,
              endLine: 269,
              symbol: "update_identity_provider",
            },
          ],
        },
      ],
      drafts: {
        github: {
          inline: [
            {
              findingId: "typed-update-kwargs-cleanup",
              body:
                "would consider extracting the PATCH body -> kwargs mapping into a helper here once this settles. this endpoint is starting to carry a lot of request-shape plumbing.",
              location: {
                file: "surelock/endpoints/sso.py",
                startLine: 238,
                endLine: 269,
                symbol: "update_identity_provider",
              },
            },
          ],
          summary: [
            "the biggest thing I would tighten here is the API contract around routing_scope nullability. runtime now rejects explicit null, but the schema snapshot still advertises null as valid.",
            "the sure_admin widening rule in the callback path also deserves explicit framing as an authz exception so the boundary stays obvious later.",
          ],
          reviewBody:
            "A couple things I would want tightened before I felt great about this.\n\n- The runtime and OpenAPI contract for routing_scope look out of sync right now: create/update reject explicit null, but the schema snapshot still advertises null as accepted. I would make that consistent one way or the other.\n- The sure_admin routing-cluster widening looks intentional, but it is a meaningful authz carveout. I would make the invariant really explicit in docs/tests that this only happens after routing-scope validation and only for SSO-issued sessions.\n\nThe overall direction makes sense and the coverage is solid. Most of my attention would stay on those boundary/contract issues.",
          recommendedState: "COMMENT",
        },
      },
    }

    return JSON.stringify(artifact, null, 2)
  },
})
