// Platform-admin overview of the vCluster Platform itself: API gateway health, auth,
// controller-runtime, inventory. Independent of scrapeMode — populated whenever the
// platform's /metrics endpoint is scraped (see the reference OTel collector's
// metrics/platform pipeline, or any equivalent scrape config).
{
  grafanaDashboards+:: {
    'vcluster-platform.json':
      (import 'source/vcluster-platform.json')
      + { tags: std.set(super.tags + $._config.grafanaTags) },
  },
}
