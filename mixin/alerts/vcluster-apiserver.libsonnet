// Apiserver alerts derive from apiserver_request_* metrics + the vcluster:apiserver_*
// recording rules built from them. Omitted when scrapeMode == 'workload' (no CP scrape).
{
  prometheusAlerts+:: {
    groups+: if $._config.scrapeMode == 'workload' then [] else [
      {
        name: 'vcluster-apiserver',
        rules: [
          {
            alert: 'VclusterAPIServerHighErrorRate',
            expr: |||
              vcluster:apiserver_request:error_rate5m
                /
              vcluster:apiserver_request:rate5m
                > 0.05
            |||,
            'for': '10m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'vCluster apiserver returning >5% 5xx errors',
              description: 'apiserver in vcluster {{ $labels.%s }} (project {{ $labels.%s }}, cluster {{ $labels.%s }}) has 5xx error rate {{ $value | humanizePercentage }} over the last 5 minutes.' % [$._config.vclusterLabels.name, $._config.vclusterLabels.project, $._config.clusterLabel],
            },
          },
          {
            alert: 'VclusterAPIServerHighErrorRate',
            expr: |||
              vcluster:apiserver_request:error_rate5m
                /
              vcluster:apiserver_request:rate5m
                > 0.20
            |||,
            'for': '5m',
            labels: { severity: 'critical' },
            annotations: {
              summary: 'vCluster apiserver returning >20% 5xx errors',
              description: 'apiserver in vcluster {{ $labels.%s }} (project {{ $labels.%s }}, cluster {{ $labels.%s }}) has 5xx error rate {{ $value | humanizePercentage }} — likely down or saturated.' % [$._config.vclusterLabels.name, $._config.vclusterLabels.project, $._config.clusterLabel],
            },
          },
          {
            alert: 'VclusterAPIServerSlowRequests',
            expr: 'vcluster:apiserver_request_duration_seconds:p99_5m > 2',
            'for': '10m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'vCluster apiserver p99 latency >2s',
              description: 'p99 request latency for apiserver in vcluster {{ $labels.%s }} (project {{ $labels.%s }}) is {{ $value | humanizeDuration }}.' % [$._config.vclusterLabels.name, $._config.vclusterLabels.project],
            },
          },
        ],
      },
    ],
  },
}
