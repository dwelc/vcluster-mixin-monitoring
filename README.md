# vcluster-mixin-monitoring

Portable monitoring bundle for vCluster **shared-nodes** fleets.

Two independent components live in this repo, designed to be used together or
separately:

| Directory | What it is | Who needs it |
| --- | --- | --- |
| [`mixin/`](mixin/) | [Jsonnet monitoring mixin](https://monitoring.mixins.dev/) — dashboards + alerts + recording rules. Slots into the customer's existing [`kubernetes-monitoring/kubernetes-mixin`](https://github.com/kubernetes-monitoring/kubernetes-mixin) build the same way that mixin does. | Anyone whose metrics already carry `vcluster_*` identity labels. |
| [`collector/`](collector/) | Reference OpenTelemetry collector Helm chart. Produces the `vcluster_*` labels via the [`k8sattributes` processor](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/k8sattributesprocessor) so the mixin's queries have something to read. | Anyone whose pipeline doesn't already enrich metrics with vCluster identity. |

## Architecture

```
 ┌─────────────────────────┐
 │  Each tenant vCluster   │
 │  ┌───────────────────┐  │
 │  │  api-server pod   │──┼──── ServiceMonitor (app=vcluster) ─┐
 │  └───────────────────┘  │                                    │
 └─────────────────────────┘                                    ▼
                                                ┌───────────────────────────┐
 ┌─────────────────────────┐                    │  OpenTelemetry Collector  │
 │  Host cluster kubelets  │                    │  (Deployment, 2 replicas) │
 │  /metrics/cadvisor      │ ─── prom scrape ──▶│                           │
 └─────────────────────────┘                    │  • TargetAllocator        │
                                                │    distributes scrapes    │
                                                │  • k8sattributes adds     │
                                                │    vcluster_* labels      │
                                                │  • filter/vcluster_only   │
                                                │    drops non-tenant data  │
                                                └─────────────┬─────────────┘
                                                              │
                                                  Prometheus remote-write
                                                              │
                                                              ▼
                                            ┌──────────────────────────────┐
                                            │  Mimir / VictoriaMetrics /   │
                                            │  Prometheus / Thanos /  ...  │
                                            └──────────────┬───────────────┘
                                                           │
                                       ┌───────────────────┼───────────────────┐
                                       ▼                   ▼                   ▼
                                  Grafana            Alertmanager      vcluster:* recording
                                (dashboards)        (alerts firing)         rule series
```

## Quickstart — just the mixin

If your pipeline already adds `vcluster_name`, `vcluster_project`, etc. labels
to metrics, you only need the mixin part.

```bash
# In your top-level mixin repo (the one that imports kubernetes-mixin):
jb install github.com/dwelc/vcluster-mixin-monitoring/mixin@main
```

In your top-level mixin entry point:

```jsonnet
(import 'kubernetes-mixin/mixin.libsonnet') +
(import 'vcluster-mixin-monitoring/mixin/mixin.libsonnet') + {
  _config+:: {
    // Override what your pipeline actually emits — these are the defaults.
    clusterLabel: 'cluster',
    vclusterLabels: {
      name: 'vcluster_name',
      project: 'vcluster_project',
      user: 'vcluster_user',
      projectNamespace: 'vcluster_project_namespace',
      virtualNamespace: 'vcluster_virtual_namespace',
      virtualPod: 'vcluster_virtual_pod',
    },
    grafanaTags: ['vcluster', 'monitoring-mixin'],  // appended to source tags
    datasource: 'prometheus',                       // your Grafana datasource UID
  },
}
```

Your existing `mixtool generate` / `jsonnet -m` build emits combined output:
`kubernetes-mixin`'s rules + ours in the same `prometheus-rules.yaml`, both
dashboard sets in the same `dashboards/` directory.

## Quickstart — also deploy the reference collector

```bash
git clone https://github.com/dwelc/vcluster-mixin-monitoring.git
cd vcluster-mixin-monitoring/collector/helm
helm dependency update

helm install vcluster-monitoring . \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.endpoint=https://mimir.example.com/api/v1/push \
  --set clusterName=prod-east-1
```

For basic auth (e.g. Grafana Cloud):

```bash
helm install vcluster-monitoring . \
  ... \
  --set prometheus.username='instance-id' \
  --set prometheus.password='your-api-key'
```

See [`collector/README.md`](collector/README.md) for the full values reference.

## What the mixin produces

`make build` (or running `mixtool generate all`) emits:

| File | Contents |
| --- | --- |
| `examples/prometheus-rules.yaml` | 6 recording rules under group `vcluster.rules`. All metrics under the `vcluster:` namespace prefix (kube-mixin convention reserves `cluster:` for itself). |
| `examples/prometheus-alerts.yaml` | 9 alerts across 3 groups: `vcluster-apiserver`, `vcluster-controlplane`, `vcluster-workload`. Severity = `warning` or `critical` per kube-mixin convention. |
| `examples/dashboards/vcluster-projects.json` | Platform-admin overview: per-project summary, resource usage, API health. 19 panels. |
| `examples/dashboards/vcluster-detail.json` | Per-vCluster drill-down: control plane health, workloads, pods, CPU/memory. 34 panels. |

### Recording rules

| Series | What it computes |
| --- | --- |
| `vcluster:apiserver_request:rate5m` | Per-vCluster apiserver request rate |
| `vcluster:apiserver_request:error_rate5m` | Per-vCluster 5xx error rate |
| `vcluster:apiserver_request_duration_seconds:p99_5m` | Per-vCluster p99 latency |
| `vcluster:pod_cpu:usage_5m` | Per-vCluster CPU usage (sum across tenant pods) |
| `vcluster:pod_memory:usage` | Per-vCluster memory working set |
| `vcluster:pod:count` | Per-vCluster pod count |

### Alerts

`vcluster-apiserver`: `VclusterAPIServerHighErrorRate` (warning >5%, critical >20%),
`VclusterAPIServerSlowRequests` (p99 >2s).

`vcluster-controlplane`: `VclusterControlPlanePodCrashLooping`,
`VclusterControlPlanePodNotReady`, `VclusterControlPlaneOOMKilled`.

`vcluster-workload`: `VclusterCPUSaturation`, `VclusterMemorySaturation`,
`VclusterPodCountDrop`.

## Building locally

Prerequisites: `jsonnet`, `jsonnetfmt`, `jb` (jsonnet-bundler), `mixtool`.

```bash
brew install go-jsonnet jsonnet-bundler
go install github.com/monitoring-mixins/mixtool/cmd/mixtool@latest
```

```bash
make build       # emit alerts + rules + dashboards to examples/
make lint        # mixtool lint
make fmt         # jsonnetfmt -i
make clean       # nuke vendor + examples
```

The repo commits the built `examples/` output so consumers can review without
running the toolchain. Re-run `make build` after changing `_config` or jsonnet
sources to refresh.

## Backend support

Anything that speaks **Prometheus remote write**:

- **Mimir** — point at the distributor's `/api/v1/push`
- **VictoriaMetrics** (vmsingle / vmcluster) — direct write to `:8428/api/v1/write`
- **Prometheus** — needs `--enable-feature=remote-write-receiver`
- **Thanos** — point at the Receive component
- **Grafana Cloud** — set `prometheus.username` + `prometheus.password`

## Troubleshooting

### "Mixin's queries return no data"

Check that your metrics actually carry the vcluster identity labels:

```bash
# Should return at least one series:
curl 'https://your-backend/api/v1/query?query=count(container_cpu_usage_seconds_total{vcluster_name!=""})'
```

If 0, your pipeline isn't enriching metrics with vcluster labels. Either deploy
the reference collector from `collector/helm/` or replicate its `k8sattributes`
processor configuration in your existing pipeline.

### "Operator rejects my Collector CR on upgrade"

The [opentelemetry-operator's validating webhook](https://github.com/open-telemetry/opentelemetry-operator/issues)
incorrectly denies `mode: deployment` + `targetAllocator.enabled: true`
combinations. Our chart's `patch-webhook` hook removes the broken DELETE
validation at install/upgrade/uninstall time. If you hit a CREATE/UPDATE block
on an upgrade, manually delete the webhook config for that single op:

```bash
kubectl delete validatingwebhookconfiguration vcluster-monitoring-opentelemetry-operator-validation
# retry your upgrade — the chart's hook recreates the webhook (minus DELETE bits)
```

### "Series have 100+ labels"

If you deploy [Node Feature Discovery](https://github.com/kubernetes-sigs/node-feature-discovery)
(e.g. via `gpu-operator`), it labels nodes with 100+ feature labels. Without
intervention, the OTel collector's kubelet scrape blanket-copies them onto
every cAdvisor series — past most prom-write backends' default limits. Our
collector chart includes a `labeldrop` for `feature_node_kubernetes_io_.*` to
strip them at scrape time.

### "UID conflicts on dashboard import"

Both dashboards keep their original UIDs (`vcluster-projects`,
`vcluster-vclusters`). If you previously imported these manually from
[the vCluster docs](https://www.vcluster.com/docs/platform/maintenance/monitoring/fleet-monitoring-otel),
delete the UI-imported copies before applying the mixin output — Grafana
refuses to provision over an existing same-UID dashboard.

## License

Apache 2.0 (matching upstream vCluster + opentelemetry-collector).
