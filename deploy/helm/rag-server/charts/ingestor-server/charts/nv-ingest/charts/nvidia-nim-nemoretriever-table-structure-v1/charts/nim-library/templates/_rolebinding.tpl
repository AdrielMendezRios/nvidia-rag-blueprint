{{- define "nim.common.v1.rolebinding" -}}
---
{{- if and .Values.serviceAccount.create (.Capabilities.APIVersions.Has "security.openshift.io/v1") }}
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{ include "nim.common.v1.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
{{- include "nim.common.v1.labels" . | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: nvidia-blueprint-ocp
subjects:
- kind: ServiceAccount
  name: {{ include "nim.common.v1.serviceAccountName" . }}
  namespace: {{ .Release.Namespace }}
{{- end }}
{{- end -}}