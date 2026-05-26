# vcluster-mixin-monitoring

Portable monitoring bundle for vCluster **shared-nodes** fleets.

Two independent components live in this repo, designed to be used together or
separately:

| Directory | What it is | Who needs it |
| --- | --- | --- |
| [`mixin/`](mixin/) | [Jsonnet monitoring mixin](https://monitoring.mixins.dev/) — dashboards + alerts + recording rules. Slots into existing [`kubernetes-monitoring/kubernetes-mixin`](https://github.com/kubernetes-monitoring/kubernetes-mixin) build. | Anyone whose metrics already carry `vcluster_*` identity labels. |
| [`collector/`](collector/) | Reference OpenTelemetry collector Helm chart. Produces the `vcluster_*` labels via the [`k8sattributes` processor](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/k8sattributesprocessor) so the mixin's queries have something to read. | Anyone whose pipeline doesn't already enrich metrics with vCluster identity. |

## Architecture

The OTel collector below is the **reference** label-enrichment path. The mixin itself
only cares that your metrics carry the `vcluster_*` identity labels — any pipeline
that produces them works equally well.

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

## Scrape modes

Some deployments scrape only the vCluster **control planes** (per-tenant apiserver
metrics via the [vCluster-published ServiceMonitor](https://www.vcluster.com/docs/vcluster/configure/vcluster-yaml/control-plane/deployment/service-monitor));
others also scrape the **workloads** running inside each
tenant via cAdvisor. The mixin supports both via `_config.scrapeMode`:

| Mode | Emits | Use when |
| --- | --- | --- |
| `'control-plane'` | `vcluster-apiserver` + `vcluster-controlplane` alert groups; the 3 `vcluster:apiserver_*` recording rules | You only have the vCluster apiserver ServiceMonitor in your scrape config — no cAdvisor enrichment. |
| `'workload'` | `vcluster-controlplane` + `vcluster-workload` alert groups; the 3 `vcluster:pod_*` recording rules | You scrape cAdvisor with vCluster identity enrichment but don't scrape the tenant apiservers. Uncommon — usually paired. |
| `'both'` (default) | All 3 alert groups, all 6 recording rules | Full pipeline (e.g. the reference OTel collector below). |

Dashboards always render in any mode — panels referencing unavailable metrics
just show "No data". The `vcluster-controlplane` alert group uses kube-state-metrics
and is emitted in every mode (it depends on `vcluster_*` labels being attached to
`kube_pod_*` series; verify your enrichment covers kube-state-metrics output if
you want these alerts to fire).

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

    // Pick which alert groups + recording rules get emitted. See "Scrape modes" above.
    scrapeMode: 'both',                             // 'control-plane' | 'workload' | 'both'

    // Metric used by dashboard template-variable dropdowns (cluster/project/vcluster).
    // Default is always-present on apiserver scrapes; only override if your pipeline
    // strips it or you need a different label-carrier metric.
    templateMetric: 'kubernetes_build_info',

    // Prometheus job label used by the vCluster Platform /metrics scrape. Only affects
    // the vCluster Platform dashboard + alert group. Override if your scrape config
    // names the job differently.
    platformJob: 'loft-platform',
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

`make build` (or running `mixtool generate all`) emits (counts shown for default `scrapeMode: 'both'`):

| File | Contents |
| --- | --- |
| `examples/prometheus-rules.yaml` | 6 recording rules under group `vcluster.rules`. All metrics under the `vcluster:` namespace prefix (kube-mixin convention reserves `cluster:` for itself). |
| `examples/prometheus-alerts.yaml` | 14 alerts across 4 groups: `vcluster-apiserver`, `vcluster-controlplane`, `vcluster-workload`, `vcluster-platform`. Severity = `warning` or `critical` per kube-mixin convention. |
| `examples/dashboards/vcluster-projects.json` | Platform-admin overview: per-project summary, resource usage, API health. 19 panels. |
| `examples/dashboards/vcluster-detail.json` | Per-vCluster drill-down: control plane health, workloads, pods, CPU/memory. 34 panels. |
| `examples/dashboards/vcluster-platform.json` | vCluster Platform self-monitoring: API gateway, auth, controller-runtime, inventory. 20 panels. |

`scrapeMode: 'control-plane'` and `'workload'` each drop one alert group + 3 recording rules. The `vcluster-platform` group is independent of `scrapeMode` and always emitted (panels show "No data" if the platform's `/metrics` isn't being scraped).

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

`vcluster-platform`: `VclusterPlatformDown` (critical),
`VclusterPlatformHighAPIErrorRate`, `VclusterPlatformHighAPILatency`,
`VclusterPlatformAuthErrorSpike`, `VclusterPlatformControllerReconcileErrors`.

## Monitoring the vCluster Platform itself

In addition to per-vCluster monitoring, the mixin ships a `vCluster / Platform`
dashboard + a `vcluster-platform` alert group that monitor the **management plane**
— the Loft / vCluster Platform pod itself. It surfaces API gateway health, OIDC
auth flow, controller-runtime reconciliation, and your project / vCluster
inventory.

This is independent of `scrapeMode` (the platform isn't a tenant), and the
platform's `/metrics` endpoint is gated by a SubjectAccessReview on the
non-resource URL `/metrics`. Your scrape agent's ServiceAccount needs:

```yaml
- nonResourceURLs: ["/metrics"]
  verbs: ["get"]
```

Most standard Prometheus/vmagent ClusterRoles already grant this.

### Setting up the scrape

Two viable approaches:

1. **Enable the bundled ServiceMonitor** in the platform's helm values:

   ```yaml
   serviceMonitor:
     enabled: true
   ```

   Your existing Prometheus / vmagent will pick it up via its ServiceMonitor
   selectors. Simplest path if you're already running a generic agent.

2. **Add a static scrape config to your OTel collector** (recommended if you
   already have a tenant-scraping OTel collector — keeps all vcluster-fleet
   metric config in one place). Add a second receiver + pipeline:

   ```yaml
   receivers:
     prometheus/platform:
       config:
         scrape_configs:
           - job_name: 'loft-platform'
             kubernetes_sd_configs:
               - role: endpoints
                 namespaces:
                   names: [vcluster-platform]
             relabel_configs:
               - source_labels: [__meta_kubernetes_service_label_loft_sh_service]
                 regex: loft
                 action: keep
               - source_labels: [__meta_kubernetes_endpoint_port_name]
                 regex: http
                 action: keep
             scheme: http
             authorization:
               credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token

   service:
     pipelines:
       metrics/platform:
         receivers: [prometheus/platform]
         processors: [memory_limiter, resource/add_cluster, batch]
         exporters: [prometheusremotewrite]
   ```

   Note this routes platform metrics through their **own** pipeline — they skip
   the `k8sattributes` + `filter/vcluster_only` processors used for tenant
   metrics (the platform has no vCluster identity to enrich).

### Job label

The dashboard + alerts default to `job="loft-platform"`. If your scrape config
uses a different job name, override `_config.platformJob` to match.

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

Check that your metrics actually carry the vcluster identity labels. Use the
metric that matches your `scrapeMode`:

```bash
# scrapeMode='control-plane' or 'both' — apiserver scrapes must be enriched:
curl 'https://your-backend/api/v1/query?query=count(kubernetes_build_info{vcluster_name!=""})'

# scrapeMode='workload' or 'both' — cAdvisor scrapes must be enriched:
curl 'https://your-backend/api/v1/query?query=count(container_cpu_usage_seconds_total{vcluster_name!=""})'
```

If 0, your pipeline isn't enriching the relevant scrape targets with vcluster
labels. Either deploy the reference collector from `collector/helm/`, or
replicate its `k8sattributes` processor configuration in your existing pipeline
(Grafana Alloy, vmagent + relabel rules, custom OTel collector, etc.).

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
