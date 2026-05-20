# collector/

Reference OpenTelemetry collector Helm chart. Produces `vcluster_*` identity
labels on every series so the [mixin's](../mixin/) queries have something to
read. Wraps the upstream
[`opentelemetry-kube-stack`](https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-kube-stack)
chart, but renders the `OpenTelemetryCollector` CR from our own template so
all customer knobs live at the chart's top-level values.

## Install

```bash
helm dependency update ./helm   # pull opentelemetry-kube-stack into ./helm/charts/

helm install vcluster-monitoring ./helm \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.endpoint=https://your-backend.example.com \
  --set clusterName=prod-east-1
```

## Values

| Key | Default | Purpose |
| --- | --- | --- |
| `prometheus.endpoint` | `""` (required) | Remote-write base URL. `/api/v1/write` is appended automatically. |
| `prometheus.username` | `""` | Optional basic-auth user. |
| `prometheus.password` | `""` | Optional basic-auth password. |
| `prometheus.insecure` | `false` | Skip TLS verification. |
| `clusterName` | `default-cluster` | Value applied as the `cluster` label on every series and as `k8s.cluster.name` resource attribute. |
| `extraHeaders` | `{}` | HTTP headers added to every remote-write request. Mimir: `{X-Scope-OrgID: my-tenant}`. |
| `replicaCount` | `2` | Collector pod count. The Target Allocator distributes scrape targets across them — bump if your tenant ServiceMonitor count grows past ~50. |
| `resources` | requests 250m/512Mi, limits 1Gi memory | Per-pod resources. |
| `image.repository` | `otel/opentelemetry-collector-contrib` | Must be the **`-contrib`** variant — the upstream image doesn't include `k8sattributes`. |
| `image.tag` | `0.144.0` | Tested version. Newer should work; older may not have `presets.kubernetesAttributes` semantics. |
| `serviceMonitorSelector` | `{matchLabels: {app: vcluster}}` | The Target Allocator scrapes ServiceMonitors matching this label set. The default matches the ServiceMonitors vCluster Platform creates per-tenant. |
| `opentelemetry-kube-stack.enabled` | `true` | Set `false` if you already run the OTel operator and just want our collector CR. |
| `opentelemetry-kube-stack.*` | — | Pass-through to the upstream chart. We disable both `collectors.daemon` and `collectors.cluster` (we provide our own CR). |

## What gets installed

| Resource | Source | Purpose |
| --- | --- | --- |
| `OpenTelemetryCollector/vcluster-monitoring-cluster` | this chart's templates | The actual collector spec — 2 replicas, Deployment mode, Target Allocator enabled. Watches ServiceMonitors with `app=vcluster` and scrapes kubelet/cadvisor directly. |
| `Deployment/vcluster-monitoring-opentelemetry-operator` | sub-chart | The OTel operator (manages the CR's pods). |
| `ValidatingWebhookConfiguration` + `MutatingWebhookConfiguration` | sub-chart | Operator admission webhooks. |
| `Job/vcluster-monitoring-patch-webhook` (post-install) | this chart | Removes the broken DELETE webhook (see `Troubleshooting` in repo root). |
| Various RBAC, ConfigMaps, Services | sub-chart | Operator plumbing. |

## Pipeline (what the collector does to each metric)

```
prometheus receiver
    │  (kubelet/cadvisor scrape +
    │   ServiceMonitors with app=vcluster)
    ▼
memory_limiter                # backpressure
groupbyattrs                  # split batches per (namespace, pod, node) — critical for correct k8sattributes
transform/pre_enrich          # promote namespace/pod/node prom labels to k8s.* resource attrs
k8sattributes                 # look up vcluster.loft.sh/* annotations + loft.sh/* namespace labels
filter/vcluster_only          # drop anything that didn't get a vcluster.name attribute
resource/add_cluster          # tag with cluster=<clusterName>
transform                     # copy resource attrs onto datapoint attrs (for prom label conversion)
batch                         # 10k samples / 10s timeout
prometheusremotewrite         # ship to backend
```

## Validation before install

```bash
# Render to YAML — check what would land:
helm template vcluster-monitoring ./helm \
  --namespace monitoring \
  --set prometheus.endpoint=https://example.com \
  --set clusterName=demo

# Server-side dry-run — schema-checks against your cluster's CRDs.
# Note: will hit the operator's known CREATE/UPDATE webhook bug; that's fine —
# the patch-webhook hook handles it at real install time.
helm template ... | kubectl apply --dry-run=client -f -
```

## Disabling the collector chart (mixin-only setups)

If your pipeline already enriches metrics with `vcluster_*` labels, you don't
need this chart — just use the mixin in `../mixin/`. See the
[repo-root README](../README.md) quickstart.
