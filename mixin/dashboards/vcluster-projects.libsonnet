// Platform-admin overview: project-summary, per-project resource usage, API health trends.
// Source JSON ships as-is (uses ${datasource} template variable — portable across backends).
// Tags from _config get merged on top.
{
  grafanaDashboards+:: {
    'vcluster-projects.json':
      (import 'source/vcluster-projects.json')
      + { tags: std.set(super.tags + $._config.grafanaTags) },
  },
}
