{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "nvidia-device-plugin.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "nvidia-device-plugin.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "nvidia-device-plugin.chart" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" $name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "nvidia-device-plugin.labels" -}}
helm.sh/chart: {{ include "nvidia-device-plugin.chart" . }}
{{ include "nvidia-device-plugin.templateLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Template labels
*/}}
{{- define "nvidia-device-plugin.templateLabels" -}}
app.kubernetes.io/name: {{ include "nvidia-device-plugin.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Values.selectorLabelsOverride }}
{{ toYaml .Values.selectorLabelsOverride }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "nvidia-device-plugin.selectorLabels" -}}
{{- if .Values.selectorLabelsOverride -}}
{{ toYaml .Values.selectorLabelsOverride }}
{{- else -}}
{{ include "nvidia-device-plugin.templateLabels" . }}
{{- end }}
{{- end }}

{{/*
Full image name with tag
*/}}
{{- define "nvidia-device-plugin.fullimage" -}}
{{- $tag := printf "v%s" .Chart.AppVersion }}
{{- .Values.image.repository -}}:{{- .Values.image.tag | default $tag -}}
{{- end }}

{{/*
Security context for the plugin
*/}}
{{- define "nvidia-device-plugin.securityContext" -}}
{{- if ne (len .Values.securityContext) 0 -}}
  {{ toYaml .Values.securityContext }}
{{- else if .Values.compatWithCPUManager -}}
  privileged: true
{{- else if ne (include "nvidia-device-plugin.allPossibleMigStrategiesAreNone" .) "true" -}}
    capabilities:
      add:
        - SYS_ADMIN
{{- else -}}
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
{{- end -}}
{{- end -}}

{{/*
Security context for GFD
*/}}
{{- define "gpu-feature-discovery.securityContext" -}}
{{- if ne (len .Values.securityContext) 0 -}}
  {{ toYaml .Values.securityContext }}
{{- else if ne (include "nvidia-device-plugin.allPossibleMigStrategiesAreNone" .) "true" -}}
    capabilities:
      add:
        - SYS_ADMIN
{{- else -}}
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
{{- end -}}
{{- end -}}

{{/*
Check if migStrategy (from all possible configurations) is "none"
*/}}
{{- define "nvidia-device-plugin.allPossibleMigStrategiesAreNone" -}}
{{- $result := true -}}
{{- if .Values.migStrategy -}}
  {{- if ne .Values.migStrategy "none" -}}
    {{- $result = false -}}
  {{- end -}}
{{- else if ne (include "nvidia-device-plugin.configMapName" .) "true" -}}
    {{- $result = false -}}
{{- else -}}
  {{- range $name, $contents := $.Values.config.map -}}
    {{- $config := $contents | fromYaml -}}
    {{- if $config.flags -}}
      {{- if ne $config.flags.migStrategy "none" -}}
        {{- $result = false -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- $result -}}
{{- end }}

{{/*
Check if an explicit set of configs has been provided or not
*/}}
{{- define "nvidia-device-plugin.hasEmbeddedConfigMap" -}}
{{- $result := true -}}
{{- if empty .Values.config.map  -}}
  {{- $result = false -}}
{{- end -}}
{{- $result -}}
{{- end }}

{{/*
Check if there is a ConfigMap in use or not
*/}}
{{- define "nvidia-device-plugin.hasConfigMap" -}}
{{- $result := false -}}
{{- if ne (include "nvidia-device-plugin.configMapName" .) "" -}}
  {{- $result = true -}}
{{- end -}}
{{- $result -}}
{{- end }}

{{/*
Get the name of the default configuration
*/}}
{{- define "nvidia-device-plugin.getDefaultConfig" -}}
{{- $result := "" -}}
{{- if .Values.config.default -}}
  {{- $result = .Values.config.default  -}}
{{- else if not (empty .Values.config.map) -}}
  {{- if hasKey .Values.config.map "default" -}}
    {{- $result = "default" -}}
  {{- else if eq (.Values.config.map | keys | len) 1 -}}
    {{- $result = (.Values.config.map | keys | first) -}}
  {{- end -}}
{{- end -}}
{{- $result -}}
{{- end }}

{{/*
Get the name of the configmap to use
*/}}
{{- define "nvidia-device-plugin.configMapName" -}}
{{- $result := "" -}}
{{- if .Values.config.name -}}
  {{- $result = .Values.config.name -}}
{{- else if not (empty .Values.config.map) -}}
  {{- $result = printf "%s-%s" (include "nvidia-device-plugin.fullname" .) "configs" -}}
{{- end -}}
{{- $result -}}
{{- end -}}

{{/*
Pod annotations for the plugin and GFD
*/}}
{{- define "nvidia-device-plugin.podAnnotations" -}}
{{- $annotations := .local.Values.podAnnotations -}}
{{- if not (hasKey $annotations "rollme") -}}
  {{- if eq (include "nvidia-device-plugin.hasEmbeddedConfigMap" .root) "true" -}}
    {{- $_ := set $annotations "rollme" (include (print $.root.Template.BasePath "/configmap.yml") .root | sha256sum) -}}
  {{- else if eq (include "nvidia-device-plugin.hasConfigMap" .root) "true" -}}
    {{- $_ := set $annotations "rollme" (randAlphaNum 5) -}}
  {{- end -}}
{{- end -}}
{{- toYaml $annotations }}
{{- end -}}
