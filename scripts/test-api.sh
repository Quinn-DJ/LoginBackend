#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
pocketbase_bin=${POCKETBASE_BIN:-/private/tmp/tastymap-pocketbase-0.40.6/pocketbase}
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/tastymap-login-test.XXXXXX")
port=${POCKETBASE_TEST_PORT:-18090}
base_url="http://127.0.0.1:${port}"
server_pid=

cleanup() {
  if [ -n "${server_pid}" ]; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
  fi
  rm -rf "$test_dir"
}
trap cleanup EXIT INT TERM

test -x "$pocketbase_bin"
command -v curl >/dev/null
command -v jq >/dev/null

env TEST_ENCRYPTION_KEY=test-encryption-key-32-character \
  "$pocketbase_bin" superuser upsert \
  "admin@example.test" "test-admin-password" \
  --dir="$test_dir/pb_data" \
  --migrationsDir="$project_dir/pb_migrations" \
  --encryptionEnv=TEST_ENCRYPTION_KEY >/dev/null

TEST_ENCRYPTION_KEY=test-encryption-key-32-character \
  "$pocketbase_bin" serve \
  --http="127.0.0.1:${port}" \
  --dir="$test_dir/pb_data" \
  --migrationsDir="$project_dir/pb_migrations" \
  --hooksDir="$project_dir/pb_hooks" \
  --encryptionEnv=TEST_ENCRYPTION_KEY >"$test_dir/server.log" 2>&1 &
server_pid=$!

attempt=0
until curl --fail --silent "${base_url}/api/health" >/dev/null; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 60 ]; then
    cat "$test_dir/server.log"
    echo "PocketBase did not become healthy" >&2
    exit 1
  fi
  sleep 0.25
done

admin_token=$(
  curl --fail --silent \
    -H "Content-Type: application/json" \
    -d '{"identity":"admin@example.test","password":"test-admin-password"}' \
    "${base_url}/api/collections/_superusers/auth-with-password" |
    jq -er '.token'
)

create_user() {
  email=$1
  name=$2
  curl --fail --silent \
    -H "Authorization: ${admin_token}" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${email}\",\"password\":\"test-user-password\",\"passwordConfirm\":\"test-user-password\",\"verified\":true,\"name\":\"${name}\"}" \
    "${base_url}/api/collections/users/records" |
    jq -er '.id'
}

user_one_id=$(
  env \
    BASE_URL="$base_url" \
    PB_ADMIN_EMAIL="admin@example.test" \
    PB_ADMIN_PASSWORD="test-admin-password" \
    USER_EMAIL="one@example.test" \
    USER_PASSWORD="test-user-password" \
    USER_NAME="User One" \
    "$project_dir/scripts/create-user.sh"
)
user_two_id=$(create_user "two@example.test" "User Two")

public_signup_status=$(
  curl --silent --output /dev/null --write-out '%{http_code}' \
    -H "Content-Type: application/json" \
    -d '{"email":"public@example.test","password":"test-user-password","passwordConfirm":"test-user-password","name":"Public User"}' \
    "${base_url}/api/collections/users/records"
)
test "$public_signup_status" -eq 403

login() {
  email=$1
  curl --fail --silent \
    -H "Content-Type: application/json" \
    -d "{\"identity\":\"${email}\",\"password\":\"test-user-password\"}" \
    "${base_url}/api/collections/users/auth-with-password" |
    jq -er '.token'
}

user_one_token=$(login "one@example.test")
user_two_token=$(login "two@example.test")

refreshed_user_one_token=$(
  curl --fail --silent \
    -X POST \
    -H "Authorization: ${user_one_token}" \
    "${base_url}/api/collections/users/auth-refresh" |
    jq -er '.token'
)
test -n "$refreshed_user_one_token"

place_payload=$(
  jq -nc \
    --arg owner "$user_one_id" \
    '{
      owner: $owner,
      client_id: "place-0001",
      name: "TastyMap Test Kitchen",
      address: "Test Road 1",
      latitude: 31.2304,
      longitude: 121.4737,
      category: "restaurant",
      tags: ["chinese", "quiet"],
      note: "integration test",
      status: "want_to_go",
      client_updated_at: "2026-10-26T12:00:00.000Z",
      deleted: false,
      last_device_id: "test-mac"
    }'
)

place_id=$(
  curl --fail --silent \
    -H "Authorization: ${refreshed_user_one_token}" \
    -H "Content-Type: application/json" \
    -d "$place_payload" \
    "${base_url}/api/collections/places/records" |
    jq -er '.id'
)

curl --fail --silent \
  -H "Authorization: ${user_one_token}" \
  "${base_url}/api/collections/places/records" |
  jq -e --arg id "$place_id" '.items | any(.id == $id)' >/dev/null

user_two_count=$(
  curl --fail --silent \
    -H "Authorization: ${user_two_token}" \
    "${base_url}/api/collections/places/records" |
    jq -er '.totalItems'
)
test "$user_two_count" -eq 0

cross_owner_payload=$(
  jq -nc \
    --arg owner "$user_one_id" \
    '{
      owner: $owner,
      client_id: "place-0002",
      name: "Cross User Place",
      latitude: 31.2304,
      longitude: 121.4737,
      status: "want_to_go",
      client_updated_at: "2026-10-26T12:01:00.000Z",
      deleted: false
    }'
)
cross_owner_status=$(
  curl --silent --output /dev/null --write-out '%{http_code}' \
    -H "Authorization: ${user_two_token}" \
    -H "Content-Type: application/json" \
    -d "$cross_owner_payload" \
    "${base_url}/api/collections/places/records"
)
test "$cross_owner_status" -eq 400 -o "$cross_owner_status" -eq 403

cross_read_status=$(
  curl --silent --output /dev/null --write-out '%{http_code}' \
    -H "Authorization: ${user_two_token}" \
    "${base_url}/api/collections/places/records/${place_id}"
)
test "$cross_read_status" -eq 404

owner_transfer_status=$(
  curl --silent --output /dev/null --write-out '%{http_code}' \
    -H "Authorization: ${user_one_token}" \
    -H "Content-Type: application/json" \
    -X PATCH \
    -d "{\"owner\":\"${user_two_id}\"}" \
    "${base_url}/api/collections/places/records/${place_id}"
)
test "$owner_transfer_status" -eq 400 -o "$owner_transfer_status" -eq 403

anonymous_count=$(
  curl --fail --silent \
    "${base_url}/api/collections/places/records" |
    jq -er '.totalItems'
)
test "$anonymous_count" -eq 0

curl --fail --silent \
  -H "Authorization: ${user_one_token}" \
  -H "Content-Type: application/json" \
  -X PATCH \
  -d '{"deleted":true,"client_updated_at":"2026-10-26T12:05:00.000Z"}' \
  "${base_url}/api/collections/places/records/${place_id}" |
  jq -e '.deleted == true' >/dev/null

delete_status=$(
  curl --silent --output /dev/null --write-out '%{http_code}' \
    -H "Authorization: ${user_one_token}" \
    -X DELETE \
    "${base_url}/api/collections/places/records/${place_id}"
)
test "$delete_status" -eq 403 -o "$delete_status" -eq 404

kill "$server_pid"
wait "$server_pid" 2>/dev/null || true
server_pid=

printf 'y\n' |
  env TEST_ENCRYPTION_KEY=test-encryption-key-32-character \
    "$pocketbase_bin" migrate down 1 \
    --dir="$test_dir/pb_data" \
    --migrationsDir="$project_dir/pb_migrations" \
    --encryptionEnv=TEST_ENCRYPTION_KEY >/dev/null 2>&1

places_table_count=$(
  sqlite3 "$test_dir/pb_data/data.db" \
    "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'places';"
)
test "$places_table_count" -eq 0

env TEST_ENCRYPTION_KEY=test-encryption-key-32-character \
  "$pocketbase_bin" migrate up \
  --dir="$test_dir/pb_data" \
  --migrationsDir="$project_dir/pb_migrations" \
    --encryptionEnv=TEST_ENCRYPTION_KEY >/dev/null 2>&1

places_table_count=$(
  sqlite3 "$test_dir/pb_data/data.db" \
    "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'places';"
)
test "$places_table_count" -eq 1

printf 'API integration tests passed\n'
