{{- define "vcluster-monitoring.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "vcluster-monitoring.fullname" -}}
{{- printf "%s-cluster" (include "vcluster-monitoring.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "vcluster-monitoring.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "vcluster-monitoring.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/component: opentelemetry-collector
{{- end -}}
