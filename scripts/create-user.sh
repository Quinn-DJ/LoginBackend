#!/bin/sh
set -eu

: "${BASE_URL:?Set BASE_URL, for example https://api.example.com}"
: "${PB_ADMIN_EMAIL:?Set PB_ADMIN_EMAIL}"
: "${PB_ADMIN_PASSWORD:?Set PB_ADMIN_PASSWORD}"
: "${USER_EMAIL:?Set USER_EMAIL}"
: "${USER_PASSWORD:?Set USER_PASSWORD}"
: "${USER_NAME:?Set USER_NAME}"

command -v curl >/dev/null
command -v jq >/dev/null

admin_token=$(
  jq -nc \
    --arg identity "$PB_ADMIN_EMAIL" \
    --arg password "$PB_ADMIN_PASSWORD" \
    '{identity: $identity, password: $password}' |
    curl --fail --silent \
      -H "Content-Type: application/json" \
      --data-binary @- \
      "${BASE_URL}/api/collections/_superusers/auth-with-password" |
    jq -er '.token'
)

payload=$(
  jq -nc \
    --arg email "$USER_EMAIL" \
    --arg password "$USER_PASSWORD" \
    --arg name "$USER_NAME" \
    '{
      email: $email,
      password: $password,
      passwordConfirm: $password,
      verified: true,
      name: $name
    }'
)

created_user=$(
  curl --fail --silent \
  -H "Authorization: ${admin_token}" \
  -H "Content-Type: application/json" \
  --data-binary "$payload" \
  "${BASE_URL}/api/collections/users/records"
)

printf '%s' "$created_user" |
  jq -r '"Created user: \(.email) (\(.id))"' >&2
printf '%s' "$created_user" |
  jq -er '.id'
