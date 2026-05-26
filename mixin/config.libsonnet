{
  _config+:: {
    // Datasource for dashboards. Override to match your Grafana setup.
    datasource: 'prometheus',
    datasourceLabel: 'Data source',

    // Cluster label set by the OTel collector's resource/add_cluster processor.
    // The reference collector sets this to .Values.clusterName.
    clusterLabel: 'cluster',

    // vCluster identity labels emitted by the reference OTel collector
    // (k8sattributes + resource_to_telemetry_conversion). Override here if your
    // pipeline uses different label names.
    vclusterLabels: {
      name: 'vcluster_name',
      project: 'vcluster_project',
      user: 'vcluster_user',
      projectNamespace: 'vcluster_project_namespace',
      virtualNamespace: 'vcluster_virtual_namespace',
      virtualPod: 'vcluster_virtual_pod',
    },

    // Tags applied to every dashboard. Useful for folder organisation in Grafana.
    grafanaTags: ['vcluster', 'monitoring-mixin'],

    // 'control-plane' = scraping only vCluster apiservers (no cAdvisor/workload data).
    // 'workload'      = scraping only tenant workloads (no control-plane metrics).
    // 'both'          = full pipeline (reference OTel collector default).
    // Gates the workload alert group + recording rules; dashboards always render
    // but workload panels show "No data" outside 'workload'/'both'.
    scrapeMode: 'both',

    // Metric used by dashboard template variables (cluster/project/vcluster dropdowns).
    // 'kubernetes_build_info' is emitted by every apiserver scrape so it works in any
    // scrapeMode. Documented here — source JSON references this metric directly.
    templateMetric: 'kubernetes_build_info',
  },
}
