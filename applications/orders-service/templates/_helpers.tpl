{{- define "orders-service.name" -}}
{{- default .Chart.Name .Values.global.applicationName | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "orders-service.namespace" -}}
{{- .Values.global.namespace | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "orders-service.labels" -}}
app.kubernetes.io/name: {{ include "orders-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Values.global.managedBy | quote }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
platform.hashicorp.com/environment: {{ .Values.global.environment | quote }}
platform.hashicorp.com/cluster-role: {{ .Values.global.clusterRole | quote }}
platform.hashicorp.com/active: {{ .Values.global.active | quote }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "orders-service.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "orders-service.componentLabels" -}}
{{ include "orders-service.labels" . }}
app.kubernetes.io/component: {{ .component | quote }}
{{- end -}}

{{- define "orders-service.securityContext" -}}
allowPrivilegeEscalation: false
capabilities:
  drop:
    - ALL
readOnlyRootFilesystem: true
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
{{- end -}}

{{- define "orders-service.podSecurityContext" -}}
runAsNonRoot: true
seccompProfile:
  type: RuntimeDefault
{{- end -}}
