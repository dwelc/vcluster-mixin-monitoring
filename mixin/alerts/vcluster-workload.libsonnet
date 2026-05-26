// Workload alerts depend on cAdvisor + kube-state-metrics + the vcluster:pod_* recording
// rules. Omitted when scrapeMode == 'control-plane'.
{
  prometheusAlerts+:: {
    groups+: if $._config.scrapeMode == 'control-plane' then [] else [
      {
        name: 'vcluster-workload',
        rules: [
          {
            // High CPU saturation across an entire vcluster (sum of all tenant pods).
            // Threshold is 80% of the requests-sum sustained for 15 min.
            alert: 'VclusterCPUSaturation',
            expr: |||
              vcluster:pod_cpu:usage_5m
                /
              (sum by (%s, %s, %s) (kube_pod_container_resource_requests{resource="cpu", %s!=""}) > 0)
                > 0.80
            ||| % [$._config.clusterLabel, $._config.vclusterLabels.project, $._config.vclusterLabels.name, $._config.vclusterLabels.name],
            'for': '15m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'vCluster CPU usage >80% of requests',
              description: 'vcluster {{ $labels.%s }} (project {{ $labels.%s }}) has been running at {{ $value | humanizePercentage }} of its CPU requests for 15 minutes.' % [$._config.vclusterLabels.name, $._config.vclusterLabels.project],
            },
          },
          {
            alert: 'VclusterMemorySaturation',
            expr: |||
              vcluster:pod_memory:usage
                /
              (sum by (%s, %s, %s) (kube_pod_container_resource_limits{resource="memory", %s!=""}) > 0)
                > 0.90
            ||| % [$._config.clusterLabel, $._config.vclusterLabels.project, $._config.vclusterLabels.name, $._config.vclusterLabels.name],
            'for': '15m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'vCluster memory usage >90% of limits',
              description: 'vcluster {{ $labels.%s }} (project {{ $labels.%s }}) is using {{ $value | humanizePercentage }} of its memory limits. OOM kills likely if sustained.' % [$._config.vclusterLabels.name, $._config.vclusterLabels.project],
            },
          },
          {
            // Sudden pod loss — early signal for tenant outages.
            alert: 'VclusterPodCountDrop',
            expr: |||
              (
                vcluster:pod:count - vcluster:pod:count offset 15m
              ) / (vcluster:pod:count offset 15m + 0.01)
                < -0.5
            |||,
            'for': '5m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'vCluster running pod count dropped >50% in 15m',
              description: 'vcluster {{ $labels.%s }} (project {{ $labels.%s }}) lost more than half its running pods in the last 15 minutes.' % [$._config.vclusterLabels.name, $._config.vclusterLabels.project],
            },
          },
        ],
      },
    ],
  },
}
