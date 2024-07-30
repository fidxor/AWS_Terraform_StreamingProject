{{- define "otelCollectorConfig" -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-opentelemetry-collector-config
data:
  otel-collector-config.yaml: |
    {{ index .Values "opentelemetry-collector" "config" | toYaml | nindent 4 }}
{{- end -}}

{{- define "opentelemetryCollectorDaemonSet" }}
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: {{ .Release.Name }}-opentelemetry-collector
  labels:
    app: opentelemetry-collector
spec:
  selector:
    matchLabels:
      app: opentelemetry-collector
  template:
    metadata:
      labels:
        app: opentelemetry-collector
    spec:
      containers:
      - name: opentelemetry-collector
        image: "{{ index .Values "opentelemetry-collector" "image" "repository" }}:{{ index .Values "opentelemetry-collector" "image" "tag" }}"
        args:
        - "--config=/conf/otel-collector-config.yaml"
        volumeMounts:
        - name: config
          mountPath: /conf
        {{- if index .Values "opentelemetry-collector" "extraVolumeMounts" }}
        {{- toYaml (index .Values "opentelemetry-collector" "extraVolumeMounts") | nindent 8 }}
        {{- end }}
        env:
        {{- if index .Values "opentelemetry-collector" "extraEnvs" }}
        {{- toYaml (index .Values "opentelemetry-collector" "extraEnvs") | nindent 8 }}
        {{- end }}
      volumes:
      - name: config
        configMap:
          name: {{ .Release.Name }}-opentelemetry-collector-config
      {{- if index .Values "opentelemetry-collector" "extraVolumes" }}
      {{- toYaml (index .Values "opentelemetry-collector" "extraVolumes") | nindent 6 }}
      {{- end }}
{{- end }}

{{ template "opentelemetryCollectorConfigMap" . }}

{{- define "otelCollectorRBAC" }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Release.Name }}-opentelemetry-collector
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: {{ .Release.Name }}-opentelemetry-collector
rules:
- apiGroups: [""]
  resources: ["pods", "nodes", "nodes/proxy"]
  verbs: ["get", "list", "watch"]
- nonResourceURLs: ["/metrics"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{ .Release.Name }}-opentelemetry-collector
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ .Release.Name }}-opentelemetry-collector
subjects:
- kind: ServiceAccount
  name: {{ .Release.Name }}-opentelemetry-collector
  namespace: {{ .Release.Namespace }}
{{- end }}

{{- define "opentelemetryCollectorConfigMap" }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-opentelemetry-collector-config
data:
  otel-collector-config.yaml: |
    {{- index .Values "opentelemetry-collector" "config" | toYaml | nindent 4 }}
{{- end }}

---
{{ template "opentelemetryCollectorDaemonSet" . }}