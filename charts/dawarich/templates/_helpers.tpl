{{/*
Redis URL: the bundled Valkey when enabled, config.redis.url otherwise
*/}}
{{- define "dawarich.redisUrl" -}}
{{- if .Values.valkey.enabled }}
  {{- $valkeyName := .Values.valkey.nameOverride | default "valkey" }}
  {{- if .Values.valkey.fullnameOverride }}
    {{- $valkeyName = .Values.valkey.fullnameOverride }}
  {{- else if not (contains $valkeyName .Release.Name) }}
    {{- $valkeyName = printf "%s-%s" .Release.Name $valkeyName }}
  {{- else }}
    {{- $valkeyName = .Release.Name }}
  {{- end }}
  {{- printf "redis://%s:%v" ($valkeyName | trunc 63 | trimSuffix "-") (dig "service" "port" 6379 .Values.valkey) }}
{{- else }}
  {{- required "config.redis.url is required when valkey.enabled is false" .Values.config.redis.url }}
{{- end }}
{{- end -}}

{{/*
Secret groups: which environment variables are sourced from which `secret.<group>` value.
`required` groups are always rendered, the others only when something is set under `secret.<group>`.
`mandatory` fields must be set whenever the group is rendered from chart values.
*/}}
{{- define "dawarich.secretSpec" -}}
database:
  required: true
  mandatory: [password]
  keys:
    password: DATABASE_PASSWORD
rails:
  required: true
  mandatory: [secret_key_base]
  keys:
    secret_key_base: SECRET_KEY_BASE
otp:
  mandatory: [encryption_primary_key, encryption_deterministic_key, encryption_key_derivation_salt]
  keys:
    encryption_primary_key: OTP_ENCRYPTION_PRIMARY_KEY
    encryption_deterministic_key: OTP_ENCRYPTION_DETERMINISTIC_KEY
    encryption_key_derivation_salt: OTP_ENCRYPTION_KEY_DERIVATION_SALT
oidc:
  mandatory: [client_id, client_secret]
  keys:
    client_id: OIDC_CLIENT_ID
    client_secret: OIDC_CLIENT_SECRET
smtp:
  mandatory: []
  keys:
    username: SMTP_USERNAME
    password: SMTP_PASSWORD
sidekiq:
  mandatory: [username, password]
  keys:
    username: SIDEKIQ_USERNAME
    password: SIDEKIQ_PASSWORD
geocoding:
  mandatory: []
  keys:
    photon_api_key: PHOTON_API_KEY
    geoapify_api_key: GEOAPIFY_API_KEY
    nominatim_api_key: NOMINATIM_API_KEY
archive:
  mandatory: [encryption_key]
  keys:
    encryption_key: ARCHIVE_ENCRYPTION_KEY
{{- end -}}

{{/*
Validates the secret values: a group is either given inline or through `existing_secret`,
and sensitive variables must not leak into `config.extraEnv`.
*/}}
{{- define "dawarich.validateSecrets" -}}
  {{- $spec := include "dawarich.secretSpec" . | fromYaml -}}
  {{- $secret := .Values.secret | default dict -}}
  {{- range $group, $def := $spec -}}
    {{- $s := index $secret $group | default dict -}}
    {{- if $s.existing_secret -}}
      {{- range $field, $_ := $def.keys -}}
        {{- if index $s $field -}}
          {{- fail (printf "secret.%s: Cannot provide '%s' when 'existing_secret' is set." $group $field) -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
    {{- range $field, $envName := $def.keys -}}
      {{- if hasKey ($.Values.config.extraEnv | default dict) $envName -}}
        {{- fail (printf "\n\nThe key '%s' was found in config.extraEnv.\nPlease use secret.%s.%s to store this sensitive data." $envName $group $field) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/* Secrets rendered by the chart */}}
{{- define "dawarich.secrets" -}}
  {{- $spec := include "dawarich.secretSpec" . | fromYaml -}}
  {{- $secret := .Values.secret | default dict -}}
  {{- range $group, $def := $spec -}}
    {{- $s := index $secret $group | default dict -}}
    {{- if and (not $s.existing_secret) (or $def.required (not (empty $s))) }}
{{ $group }}:
  stringData:
      {{- range $field, $envName := $def.keys }}
        {{- $val := index $s $field }}
        {{- if has $field $def.mandatory }}
          {{- $val = required (printf "secret.%s.%s is required" $group $field) $val }}
        {{- end }}
        {{- if $val }}
    {{ $envName }}: {{ $val | toString | quote }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/* Secret references shared by the web and sidekiq containers */}}
{{- define "dawarich.envFrom" -}}
  {{- $spec := include "dawarich.secretSpec" . | fromYaml -}}
  {{- $secret := .Values.secret | default dict -}}
  {{- range $group, $def := $spec -}}
    {{- $s := index $secret $group | default dict }}
    {{- if $s.existing_secret }}
- secret: {{ $s.existing_secret }}
    {{- else if or $def.required (not (empty $s)) }}
- secret: {{ $group }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Non-sensitive environment variables.
Usage: include "dawarich.env" (dict "root" . "role" "web")  # role is "web" or "sidekiq"
Unset (null or empty) values are omitted so the application defaults apply.
*/}}
{{- define "dawarich.env" -}}
{{- $root := .root -}}
{{- $c := $root.Values.config -}}
{{- $pairs := list
  (list "RAILS_ENV" $c.rails.env)
  (list "RAILS_LOG_TO_STDOUT" $c.rails.log_to_stdout)
  (list "RAILS_MAX_THREADS" $c.rails.max_threads)
  (list "RAILS_CACHE_DB" $c.redis.cache_db)
  (list "RAILS_JOB_QUEUE_DB" $c.redis.job_queue_db)
  (list "RAILS_WS_DB" $c.redis.ws_db)
  (list "REDIS_URL" (include "dawarich.redisUrl" $root))
  (list "DATABASE_HOST" (required "config.database.host is required" $c.database.host))
  (list "DATABASE_PORT" $c.database.port)
  (list "DATABASE_NAME" (required "config.database.name is required" $c.database.name))
  (list "DATABASE_USERNAME" (required "config.database.user is required" $c.database.user))
  (list "SELF_HOSTED" $c.selfhosted)
  (list "APPLICATION_HOSTS" (join "," $c.application.hosts))
  (list "APPLICATION_PROTOCOL" $c.protocol)
  (list "DOMAIN" $c.application.domain)
  (list "TIME_ZONE" $c.timezone)
  (list "DISTANCE_UNIT" $c.distance_unit)
  (list "MIN_MINUTES_SPENT_IN_CITY" $c.min_minutes_spent_in_city)
  (list "STORE_GEODATA" $c.geocoding.store_geodata)
  (list "PHOTON_API_HOST" $c.geocoding.photon.host)
  (list "PHOTON_API_USE_HTTPS" $c.geocoding.photon.use_https)
  (list "NOMINATIM_API_HOST" $c.geocoding.nominatim.host)
  (list "NOMINATIM_API_USE_HTTPS" $c.geocoding.nominatim.use_https)
  (list "OIDC_ISSUER" $c.oidc.issuer)
  (list "OIDC_REDIRECT_URI" $c.oidc.redirect_uri)
  (list "OIDC_PROVIDER_NAME" $c.oidc.provider_name)
  (list "OIDC_AUTO_REGISTER" $c.oidc.auto_register)
  (list "OIDC_PKCE_ENABLED" $c.oidc.pkce_enabled)
  (list "OIDC_HOST" $c.oidc.host)
  (list "OIDC_SCHEME" $c.oidc.scheme)
  (list "OIDC_PORT" $c.oidc.port)
  (list "OIDC_AUTHORIZATION_ENDPOINT" $c.oidc.authorization_endpoint)
  (list "OIDC_TOKEN_ENDPOINT" $c.oidc.token_endpoint)
  (list "OIDC_USERINFO_ENDPOINT" $c.oidc.userinfo_endpoint)
  (list "ALLOW_EMAIL_PASSWORD_REGISTRATION" $c.allow_email_password_registration)
  (list "ALLOW_EMAIL_PASSWORD_LOGIN" $c.allow_email_password_login)
  (list "SMTP_SERVER" $c.smtp.server)
  (list "SMTP_PORT" $c.smtp.port)
  (list "SMTP_DOMAIN" $c.smtp.domain)
  (list "SMTP_FROM" $c.smtp.from)
  (list "SMTP_AUTHENTICATION" $c.smtp.authentication)
  (list "SMTP_STARTTLS" $c.smtp.starttls)
  (list "SMTP_OPEN_TIMEOUT" $c.smtp.open_timeout)
  (list "SMTP_READ_TIMEOUT" $c.smtp.read_timeout)
  (list "ARCHIVE_RAW_DATA" $c.archive_raw_data)
  (list "PUID" $c.puid)
  (list "PGID" $c.pgid)
-}}
{{- if eq .role "web" -}}
  {{- $pairs = concat $pairs (list
    (list "WEB_CONCURRENCY" $c.web.concurrency)
    (list "PROMETHEUS_EXPORTER_ENABLED" $c.prometheus.enabled)
    (list "PROMETHEUS_EXPORTER_HOST" $c.prometheus.host)
    (list "PROMETHEUS_EXPORTER_PORT" $c.prometheus.port)
  ) -}}
{{- else -}}
  {{- /* Only the web container may run the exporter, otherwise metrics are duplicated */ -}}
  {{- $pairs = concat $pairs (list
    (list "BACKGROUND_PROCESSING_CONCURRENCY" $c.sidekiq.concurrency)
    (list "PROMETHEUS_EXPORTER_ENABLED" false)
  ) -}}
{{- end -}}
{{- $env := dict -}}
{{- range $pair := $pairs -}}
  {{- $val := index $pair 1 -}}
  {{- if and (not (kindIs "invalid" $val)) (ne (toString $val) "") -}}
    {{- $_ := set $env (index $pair 0) (toString $val) -}}
  {{- end -}}
{{- end -}}
{{- range $key, $val := ($c.extraEnv | default dict) -}}
  {{- $_ := set $env $key (toString $val) -}}
{{- end -}}
{{- toYaml $env -}}
{{- end -}}
