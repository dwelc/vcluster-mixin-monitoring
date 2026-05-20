// Recording rules pre-compute aggregations that dashboards + alerts hit on every refresh.
// Prefix `vcluster:` follows the kube-mixin convention (`cluster:` reserved for kube-mixin).
{
  prometheusRules+:: {
    groups+: [
      {
        name: 'vcluster.rules',
        rules: [
          {
            // Per-vCluster apiserver request rate (any verb, any code).
            // Filter to vcluster-tagged series only — keeps a phantom no-label aggregate out.
            record: 'vcluster:apiserver_request:rate5m',
            expr: 'sum by (%s, %s, %s) (rate(apiserver_request_total{%s!=""}[5m]))' % [$._config.clusterLabel, $._config.vclusterLabels.project, $._config.vclusterLabels.name, $._config.vclusterLabels.name],
          },
          {
            // Per-vCluster apiserver 5xx error rate.
            record: 'vcluster:apiserver_request:error_rate5m',
            expr: 'sum by (%s, %s, %s) (rate(apiserver_request_total{code=~"5..", %s!=""}[5m]))' % [$._config.clusterLabel, $._config.vclusterLabels.project, $._config.vclusterLabels.name, $._config.vclusterLabels.name],
          },
          {
            // Per-vCluster apiserver p99 latency.
            // Exclude WATCH/WATCHLIST verbs — long-poll requests legitimately last 60s+
            // and would otherwise pin the p99 to the histogram's max finite bucket.
            // Same convention as upstream kubernetes-mixin.
            record: 'vcluster:apiserver_request_duration_seconds:p99_5m',
            expr: 'histogram_quantile(0.99, sum by (%s, %s, %s, le) (rate(apiserver_request_duration_seconds_bucket{verb!~"WATCH|WATCHLIST", %s!=""}[5m])))' % [$._config.clusterLabel, $._config.vclusterLabels.project, $._config.vclusterLabels.name, $._config.vclusterLabels.name],
          },
          {
            // Per-vCluster total CPU usage (sum across all tenant pods).
            record: 'vcluster:pod_cpu:usage_5m',
            expr: 'sum by (%s, %s, %s) (rate(container_cpu_usage_seconds_total{%s!="", container!=""}[5m]))' % [$._config.clusterLabel, $._config.vclusterLabels.project, $._config.vclusterLabels.name, $._config.vclusterLabels.name],
          },
          {
            // Per-vCluster total memory working set.
            record: 'vcluster:pod_memory:usage',
            expr: 'sum by (%s, %s, %s) (container_memory_working_set_bytes{%s!="", container!=""})' % [$._config.clusterLabel, $._config.vclusterLabels.project, $._config.vclusterLabels.name, $._config.vclusterLabels.name],
          },
          {
            // Per-vCluster count of pods (any phase reporting metrics).
            // We count distinct k8s_pod_name on the OTel-enriched cAdvisor stream;
            // kube_pod_status_phase is from kube-state-metrics (not OTel-enriched, no vcluster labels).
            record: 'vcluster:pod:count',
            expr: 'count by (%s, %s, %s) (group by (%s, %s, %s, k8s_pod_name) (container_memory_working_set_bytes{%s!="", k8s_pod_name!=""}))' % [$._config.clusterLabel, $._config.vclusterLabels.project, $._config.vclusterLabels.name, $._config.clusterLabel, $._config.vclusterLabels.project, $._config.vclusterLabels.name, $._config.vclusterLabels.name],
          },
        ],
      },
    ],
  },
}
