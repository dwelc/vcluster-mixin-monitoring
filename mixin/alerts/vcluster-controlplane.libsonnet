{
  prometheusAlerts+:: {
    groups+: [
      {
        name: 'vcluster-controlplane',
        rules: [
          {
            alert: 'VclusterControlPlanePodCrashLooping',
            expr: 'increase(kube_pod_container_status_restarts_total{%s!=""}[15m]) > 3' % $._config.vclusterLabels.name,
            'for': '5m',
            labels: { severity: 'critical' },
            annotations: {
              summary: 'vCluster control plane pod crash-looping',
              description: 'Pod {{ $labels.pod }} in vcluster {{ $labels.%s }} (project {{ $labels.%s }}) restarted {{ $value }} times in 15 minutes.' % [$._config.vclusterLabels.name, $._config.vclusterLabels.project],
            },
          },
          {
            alert: 'VclusterControlPlanePodNotReady',
            expr: |||
              sum by (%s, %s, %s, pod) (
                kube_pod_status_phase{%s!="", phase!~"Running|Succeeded"}
              ) > 0
            ||| % [$._config.clusterLabel, $._config.vclusterLabels.project, $._config.vclusterLabels.name, $._config.vclusterLabels.name],
            'for': '10m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'vCluster control plane pod not ready',
              description: 'Pod {{ $labels.pod }} in vcluster {{ $labels.%s }} (project {{ $labels.%s }}) has been not-ready for 10 minutes.' % [$._config.vclusterLabels.name, $._config.vclusterLabels.project],
            },
          },
          {
            alert: 'VclusterControlPlaneOOMKilled',
            expr: 'increase(kube_pod_container_status_last_terminated_reason{reason="OOMKilled", %s!=""}[15m]) > 0' % $._config.vclusterLabels.name,
            labels: { severity: 'warning' },
            annotations: {
              summary: 'vCluster control plane pod OOMKilled',
              description: 'Container {{ $labels.container }} in pod {{ $labels.pod }} (vcluster {{ $labels.%s }}, project {{ $labels.%s }}) was OOMKilled in the last 15 minutes.' % [$._config.vclusterLabels.name, $._config.vclusterLabels.project],
            },
          },
        ],
      },
    ],
  },
}
