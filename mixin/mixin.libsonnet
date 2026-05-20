// vcluster-mixin-monitoring entry point.
// Standard kube-mixin contract: { grafanaDashboards, prometheusAlerts, prometheusRules }.
(import 'config.libsonnet') +
(import 'dashboards/dashboards.libsonnet') +
(import 'alerts/alerts.libsonnet') +
(import 'rules/rules.libsonnet')
