{{- define "otelCollectorConfig" -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}otelcollectorconfig
data:
  otelcollectorconfig.yaml: |
    {{ .Values.opentelemetrycollector.config | toYaml | nindent 4 }}
{{- end -}}

{{- define "opentelemetryCollectorDaemonSet" }}
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: {{ .Release.Name }}-opentelemetrycollector
  labels:
    app: opentelemetrycollector
spec:
  selector:
    matchLabels:
      app: opentelemetrycollector
  template:
    metadata:
      labels:
        app: opentelemetrycollector
    spec:
      containers:
      - name: opentelemetrycollector
        image: "{{ .Values.opentelemetrycollector.image.repository }}:{{ .Values.opentelemetrycollector.image.tag }}"
        args:
        - "--config=/conf/otel-collector-config.yaml"
        volumeMounts:
        - name: config
          mountPath: /conf
        {{- if .Values.opentelemetrycollector.extraVolumeMounts }}
        {{- toYaml .Values.opentelemetrycollector.extraVolumeMounts | nindent 8 }}
        {{- end }}
        env:
        {{- if .Values.opentelemetrycollector.extraEnvs }}
        {{- toYaml .Values.opentelemetrycollector.extraEnvs | nindent 8 }}
        {{- end }}
      volumes:
      - name: config
        configMap:
          name: {{ .Release.Name }}-opentelemetrycollector-config
      {{- if .Values.opentelemetrycollector.extraVolumes }}
      {{- toYaml .Values.opentelemetrycollector.extraVolumes | nindent 6 }}
      {{- end }}
{{- end }}

{{ template "opentelemetryCollectorConfigMap" . }}

{{ define "otelCollectorRBAC" }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Release.Name }}opentelemetrycollector
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: {{ .Release.Name }}-opentelemetrycollector
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
  name: {{ .Release.Name }}-opentelemetrycollector
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ .Release.Name }}-opentelemetrycollector
subjects:
- kind: ServiceAccount
  name: {{ .Release.Name }}-opentelemetrycollector
  namespace: {{ .Release.Namespace }}
{{ end }}

{{- define "opentelemetryCollectorConfigMap" }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-opentelemetrycollector-config
data:
  otel-collector-config.yaml: |
    {{- toYaml .Values.opentelemetrycollector.config | nindent 4 }}
{{- end }}

---
{{ template "opentelemetryCollectorDaemonSet" . }}