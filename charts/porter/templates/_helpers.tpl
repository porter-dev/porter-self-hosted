{{/*
Expand the name of the chart.
*/}}
{{- define "porter.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "porter.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "porter.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "porter.labels" -}}
helm.sh/chart: {{ include "porter.chart" . }}
{{ include "porter.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "porter.selectorLabels" -}}
app.kubernetes.io/name: {{ include "porter.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Provisioner selector labels
*/}}
{{- define "provisioner.selectorLabels" -}}
app.kubernetes.io/name: {{ include "porter.name" . }}-provisioner
app.kubernetes.io/instance: {{ .Release.Name }}-provisioner
{{- end }}

{{/*
Worker pool selector labels
*/}}
{{- define "workerPool.selectorLabels" -}}
app.kubernetes.io/name: {{ include "porter.name" . }}-worker-pool
app.kubernetes.io/instance: {{ .Release.Name }}-worker-pool
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "porter.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "porter.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "porter.postgresql.fullname" -}}
{{- $name := default "postgresql" .Values.postgresql.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "porter.redis.fullname" -}}
{{- $name := default "redis" .Values.redis.nameOverride -}}
{{- printf "%s-%s-master" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
