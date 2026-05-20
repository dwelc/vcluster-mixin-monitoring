// Per-vCluster drill-down: pods, CPU, memory, error rate, control plane health.
{
  grafanaDashboards+:: {
    'vcluster-detail.json':
      (import 'source/vcluster-detail.json')
      + { tags: std.set(super.tags + $._config.grafanaTags) },
  },
}
