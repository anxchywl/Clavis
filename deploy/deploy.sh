#!/bin/sh
# builds the current revision and replaces the running service with it,
# restoring the previous image if anything below fails
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
env_file=${ENV_FILE:-$repo_dir/.env.production}
deploy_ref=${DEPLOY_REF:-$(git -C "$repo_dir" rev-parse --verify HEAD)}
image="clavis-backend:$deploy_ref"
compose="docker compose --env-file $env_file -f $repo_dir/docker/docker-compose.production.yml"

# a host already running another project's caddy on 80/443 fronts clavis
# through that proxy instead of publishing a port of its own
target=${DEPLOYMENT_TARGET:-}
if [ -z "$target" ]; then
  if docker ps --format '{{.Names}}' | grep -qx wished-caddy; then
    target=shared-host
  else
    target=dedicated
  fi
fi
if [ "$target" = "shared-host" ]; then
  compose="$compose -f $repo_dir/docker/docker-compose.shared-host.yml"
fi

previous_image=$($compose ps -q clavis-api | xargs -r docker inspect --format '{{.Config.Image}}')

DEPLOYMENT_TARGET=$target ENV_FILE=$env_file "$repo_dir/deploy/preflight.sh"

# another project on this host logs docker in to ghcr.io with a token that
# expires, and a stale login fails even anonymous pulls of public images, so
# the build reads no shared registry credentials at all
build_config=$(mktemp -d)
if ! DOCKER_CONFIG=$build_config docker build --pull --tag "$image" \
  --file "$repo_dir/backend/Dockerfile" "$repo_dir"; then
  rm -rf "$build_config"
  exit 1
fi
rm -rf "$build_config"

rollback() {
  status=$?
  if [ "$status" -ne 0 ] && [ -n "$previous_image" ]; then
    echo "deployment failed; restoring previous backend image" >&2
    BACKEND_IMAGE=$previous_image $compose up -d --no-deps clavis-api
  fi
  exit "$status"
}
trap rollback EXIT INT TERM

BACKEND_IMAGE=$image $compose up -d --remove-orphans

attempt=0
until curl --fail --silent --show-error --max-time 8 \
  "https://$(sed -n 's/^CLAVIS_API_DOMAIN=//p' "$env_file" | head -1)/health/ready" >/dev/null; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 30 ] || exit 1
  sleep 2
done

trap - EXIT INT TERM
echo "deployment completed: $deploy_ref"
