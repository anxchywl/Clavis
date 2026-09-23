#!/bin/sh
# refuses a deployment that would ship a development mechanism or an
# unauthenticated service; runs before anything is built
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
env_file=${ENV_FILE:-$repo_dir/.env.production}
target=${DEPLOYMENT_TARGET:-dedicated}

fail() {
  echo "preflight: $1" >&2
  exit 1
}

[ -f "$env_file" ] || fail "$env_file is missing"

value_of() {
  sed -n "s/^$1=//p" "$env_file" | head -1
}

[ "$(value_of APP_ENV)" = "production" ] || fail "APP_ENV must be production"
[ "$(value_of AUTH_ADAPTER)" = "host" ] || fail "AUTH_ADAPTER must be host"

# a service nobody can authenticate against is not worth deploying, and the
# resolver would reject every request rather than say why
[ -n "$(value_of HOST_JWT_ISSUER)" ] || fail "HOST_JWT_ISSUER is required"
if [ -z "$(value_of HOST_JWT_PUBLIC_KEY)" ] && [ -z "$(value_of HOST_JWT_SECRET)" ]; then
  fail "a host signing key or shared secret is required"
fi

[ -n "$(value_of CLAVIS_API_DOMAIN)" ] || fail "CLAVIS_API_DOMAIN is required"

if [ -n "$(value_of DEVELOPMENT_AUTH_TOKEN)" ] ||
  [ -n "$(value_of DEVELOPMENT_OPERATOR_AUTH_TOKEN)" ]; then
  fail "development tokens must not be present in a production environment"
fi

[ "$(value_of API_DOCS_ENABLED)" != "true" ] || fail "API_DOCS_ENABLED must be false"
[ -z "$(value_of DEVELOPMENT_CLOCK)" ] || fail "DEVELOPMENT_CLOCK must not be set"

if [ "$target" = "shared-host" ]; then
  docker network inspect wished_wished-app >/dev/null 2>&1 ||
    fail "the shared proxy network wished_wished-app does not exist"
fi

# the backup container writes here as the image's fixed user
[ "$(stat -c %u /var/backups/clavis 2>/dev/null)" = "10001" ] ||
  fail "/var/backups/clavis must exist and belong to uid 10001"

git -C "$repo_dir" diff --quiet HEAD ||
  fail "the working tree is dirty; deploy a committed revision"

echo "preflight: ok ($target)"
