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
            // One unavailable aggregated APIService degrades discovery cluster-wide.
            alert: 'VclusterAggregatedAPIDown',
            expr: |||
              max by (name, %s, %s, %s) (avg_over_time(aggregator_unavailable_apiservice[5m])) > 0.5
            ||| % [$._config.vclusterLabels.name, $._config.vclusterLabels.project, $._config.clusterLabel],
            'for': '5m',
            labels: { severity: 'critical' },
            annotations: {
              summary: 'Aggregated APIService {{ $labels.name }} is unavailable',
              description: 'APIService {{ $labels.name }} in vcluster {{ $labels.%s }} (project {{ $labels.%s }}, cluster {{ $labels.%s }}) has been unavailable for most of the last 5m. Unavailable aggregated APIs stall discovery and degrade the whole apiserver.' % [$._config.vclusterLabels.name, $._config.vclusterLabels.project, $._config.clusterLabel],
            },
          },
          {
            alert: 'VclusterAggregatedAPIErrors',
            expr: |||
              sum by (name, %s, %s, %s) (increase(aggregator_unavailable_apiservice_total[10m])) > 4
            ||| % [$._config.vclusterLabels.name, $._config.vclusterLabels.project, $._config.clusterLabel],
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Aggregated APIService {{ $labels.name }} is flapping',
              description: 'APIService {{ $labels.name }} in vcluster {{ $labels.%s }} (project {{ $labels.%s }}) reported unavailable {{ $value | humanize }} times in 10m.' % [$._config.vclusterLabels.name, $._config.vclusterLabels.project],
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
