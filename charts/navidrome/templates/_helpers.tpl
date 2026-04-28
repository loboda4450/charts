{{/*
Check for sensitive keys in .Values.config and fail if found
*/}}
{{- define "navidrome.validateSensitiveConfig" -}}
  {{- $sensitiveKeys := list "LastFM.ApiKey" "LastFM.Secret" "Prometheus.Password" -}}
  {{- range $key := $sensitiveKeys -}}
    {{- if hasKey $.Values.config $key -}}
      {{- fail (printf "\n\nThe key '%s' was found in Values.config.\nPlease remove it and use a dedicated Secret to store this sensitive data." $key) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Check for keys with ND_ prefix in .Values.config and fail if found
*/}}
{{- define "navidrome.validateNDConfig" -}}
  {{- range $key, $_ := $.Values.config -}}
    {{- if hasPrefix "ND_" $key -}}
      {{- fail (printf "\n\nThe key '%s' was found in Values.config.\nPlease use config-file keys instead of environment variables." $key) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Validates that only one secret method is used for a given service.
Usage: {{ include "mychart.validateSecret" (dict "context" . "service" .Values.secret.spotify "name" "Spotify") }}
*/}}
{{- define "navidrome.validateSecret" -}}
  {{- if .service -}}
    {{- if and .service.existing_secret (or .service.id .service.secret .service.api_key) -}}
      {{- fail (printf "%s: Cannot provide manual credentials (id/secret/api_key) when 'existing_secret' is set." .name) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}