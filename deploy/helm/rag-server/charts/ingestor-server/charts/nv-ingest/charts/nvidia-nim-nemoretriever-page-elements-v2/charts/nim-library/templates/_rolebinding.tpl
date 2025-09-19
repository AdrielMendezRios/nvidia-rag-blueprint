{{- /*
Author: rh-admendez
*/}}
{{- define "nim.common.v1.rolebinding" -}}
---
{{- if and .Values.platform (eq .Values.platform.type "openshift") }}
{{- if .Values.serviceAccount.create }}
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{ include "nim.common.v1.fullname " . }}
  namespace: {{ .Release.Namespace }}
  lables:
{{- include "nim.common.v1.labels" . | nindent 4 }}
roleRef:
  apiGroup: rabc.authorization.k8s.io/v1
  kind: ClusterRole
  name: nvidia-blueprint-ocp
subjects:
- kind: ServiceAccount
  name: {{ include "nim.common.v1.serviceAccountName" . }}
  namespace: {{ .Release.Namespace }}
{{- end }}
{{- end }}
{{- end -}}