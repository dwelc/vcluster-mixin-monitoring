// vCluster Platform (Loft) self-monitoring alerts. These fire on the management plane
// itself — apiserver/auth/controller-runtime metrics emitted by the platform's /metrics
// endpoint. Independent of scrapeMode; the user just needs to scrape the platform.
{
  prometheusAlerts+:: {
    groups+: [
      {
        name: 'vcluster-platform',
        rules: [
          {
            // Hard down: nothing scraping the platform job for 5 min.
            alert: 'VclusterPlatformDown',
            expr: 'up{job="%s"} == 0' % $._config.platformJob,
            'for': '5m',
            labels: { severity: 'critical' },
            annotations: {
              summary: 'vCluster Platform target is down',
              description: 'Prometheus scrape of the vCluster Platform "{{ $labels.%s }}" has been failing for 5 minutes.' % $._config.clusterLabel,
            },
          },
          {
            // 5xx rate on the API gateway > 5% — the user-visible API surface is broken.
            alert: 'VclusterPlatformHighAPIErrorRate',
            expr: |||
              sum by (%s) (rate(apigateway_kubernetes_request_total{job="%s",code=~"5.."}[5m]))
                /
              sum by (%s) (rate(apigateway_kubernetes_request_total{job="%s"}[5m]))
                > 0.05
            ||| % [$._config.clusterLabel, $._config.platformJob, $._config.clusterLabel, $._config.platformJob],
            'for': '10m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'vCluster Platform API gateway returning >5% 5xx errors',
              description: 'API gateway in cluster "{{ $labels.%s }}" has 5xx error rate {{ $value | humanizePercentage }} over the last 5 minutes.' % $._config.clusterLabel,
            },
          },
          {
            // p99 on user-driven API requests > 1s. Note the (?i) — apigateway uses lowercase
            // verb labels (watch/list/get), unlike kube-apiserver (WATCH/LIST/GET).
            alert: 'VclusterPlatformHighAPILatency',
            expr: |||
              histogram_quantile(0.99,
                sum by (%s, le) (
                  rate(apigateway_kubernetes_request_duration_seconds_bucket{job="%s", verb!~"(?i)WATCH|WATCHLIST|PROXY|CONNECT"}[5m])
                )
              ) > 1
            ||| % [$._config.clusterLabel, $._config.platformJob],
            'for': '15m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'vCluster Platform API p99 latency >1s',
              description: 'API gateway p99 latency in cluster "{{ $labels.%s }}" is {{ $value | humanizeDuration }} — usually <100ms.' % $._config.clusterLabel,
            },
          },
          {
            // 4xx/5xx on the apigateway /auth/* paths — failed logins, broken OIDC callbacks,
            // expired tokens, password mismatches, etc.
            alert: 'VclusterPlatformAuthErrorSpike',
            expr: 'sum by (%s) (rate(apigateway_auth_request_total{job="%s",code=~"4..|5.."}[5m])) > 0.1' % [$._config.clusterLabel, $._config.platformJob],
            'for': '10m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'vCluster Platform auth requests failing',
              description: 'Cluster "{{ $labels.%s }}" is seeing {{ $value | humanize }} failed auth requests/sec (4xx/5xx on /auth/* paths) — investigate OIDC / login flow.' % $._config.clusterLabel,
            },
          },
          {
            // controller-runtime reconcile errors are emitted when a controller fails to reconcile
            // a resource (transient or stuck state). Sustained > 0 means a controller is failing.
            alert: 'VclusterPlatformControllerReconcileErrors',
            expr: 'sum by (%s, controller) (rate(controller_runtime_reconcile_errors_total{job="%s"}[5m])) > 0' % [$._config.clusterLabel, $._config.platformJob],
            'for': '15m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'vCluster Platform controller failing to reconcile',
              description: 'Controller "{{ $labels.controller }}" in cluster "{{ $labels.%s }}" has been failing reconciles at {{ $value | humanize }}/sec for 15 minutes.' % $._config.clusterLabel,
            },
          },
        ],
      },
    ],
  },
}
