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
  },
}
