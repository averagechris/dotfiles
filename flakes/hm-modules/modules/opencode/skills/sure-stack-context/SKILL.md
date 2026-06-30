---
name: sure-stack-context
description: Use on suremac when investigating Sure production, sandbox, or QA issues across Sentry, Datadog/Pup, Kubernetes/kubectl, service ownership, traces, logs, or deployed-environment behavior.
---

# Sure Stack Context

Use for Sure debugging when Chris pastes a Sentry link, Datadog query/link, or
asks what's happening in sandbox/QA/production.

## First moves

- Use the private hints below to pick likely services/ecosystems before broad
  rediscovery.
- Use `sentry` for issue/event details, `pup` for Datadog logs/traces/metrics,
  and `kubectl` for live deployed state.
- Start narrow: environment, shard/namespace, service, trace/event ID, timestamp,
  request path, pod/deployment, or worker queue.
- Prefer read-only commands. Ask before mutations such as restart, scale, delete,
  apply, patch, exec, or secret/config changes.
- Keep output small: aggregate/list first, then fetch representative details.

## Kubernetes workflow

Use the Kubernetes context that Chris asks for, or infer it from the evidence
(for example production vs sandbox/QA links, logs, or wording). Do not switch
away from the current context just because it is local; local contexts may be
intentional.

Shards often map to Kubernetes namespaces. Once you know or suspect the relevant
namespace, inspect app services, workers, cronjobs, and routes there:

```bash
kubectl --context CONTEXT get ns --show-labels
kubectl --context CONTEXT get deploy,svc,pods,job,cronjob -n NAMESPACE
kubectl --context CONTEXT get hpa -n NAMESPACE
kubectl --context CONTEXT get virtualservice -n NAMESPACE
kubectl --context CONTEXT describe pod -n NAMESPACE POD
kubectl --context CONTEXT logs -n NAMESPACE POD --since=30m --tail=200
kubectl --context CONTEXT get events -n NAMESPACE --sort-by=.lastTimestamp
```

Look for API deployments, worker deployments, cronjobs/jobs, pod restarts,
rollouts, HPA/scaling events, Datadog pod tags, and VirtualServices/routes. KEDA
details may be RBAC-restricted.

Correlate tools: Sentry identifies exception/release; Datadog explains traces,
logs, and dependencies; Kubernetes confirms rollout, pod health, restarts,
scaling, and namespace-specific sandbox behavior.

## Private appendix

Use the private context below for service/ecosystem filters. Do not copy it into
public files or public chat output.
