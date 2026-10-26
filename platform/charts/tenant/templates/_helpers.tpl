{{/* Namespace of the tenant. */}}
{{- define "tenant.namespace" -}}
tenant-{{ required "name is required (pass the tenant file with -f)" .Values.name }}
{{- end -}}

{{/* Labels on every object. Values are quoted because they come from the tenant file. */}}
{{- define "tenant.labels" -}}
app.kubernetes.io/managed-by: k8s-tenant-platform
tenant: {{ .Values.name | quote }}
team: {{ .Values.owner.team | quote }}
cost-centre: {{ .Values.costCentre | quote }}
environment: {{ .Values.environment | quote }}
{{- end -}}

{{/* The size tier chosen by the tenant, as YAML. Fails with a clear message for an unknown size. */}}
{{- define "tenant.tier" -}}
{{- $tier := get .Values.sizes (toString .Values.size) -}}
{{- if not $tier -}}
{{- fail (printf "unknown size %q, expected one of: small, medium, large" (toString .Values.size)) -}}
{{- end -}}
{{- toYaml $tier -}}
{{- end -}}
