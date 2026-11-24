#!/usr/bin/env bash
# Builds this checkout and makes it the active relay release on this computer,
# without a GitHub release. For working on the fork: commit, then run this.
#
#   scripts/deploy-local.sh            rebuild the phone app (web/), package, install, restart, verify
#   scripts/deploy-local.sh --no-web   reuse web/ as it is (a relay-only change)
#
# It installs the same way install.sh does (verify-release, seal-release,
# prune-releases keeping the previous release, activate-release), restarts the
# relay's service, and waits for /readyz to report this version, revision and
# web build. If the new release never becomes ready, it reactivates the
# previous one. The release is named after HEAD, so commit before deploying
# again: a commit that is already installed is refused.
#
# The rebuilt web/ is left in the working tree; commit it with the change.
# Needs Go, and for the web build Bun 1.4.4 and Node 26 on PATH.
set -euo pipefail

die() { echo "deploy-local: $*" >&2; exit 1; }

repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"
build_web=1
case "${1:-}" in
    "") ;;
    --no-web) build_web=0 ;;
    *) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac

release_root=${HERDR_RELEASE_ROOT:-$HOME/.local/share/herdr-mobile-relay}
binary=herdr-mobile-relay
case "$(uname -s)/$(uname -m)" in
    Darwin/arm64) target=darwin/arm64 ;;
    Darwin/x86_64) target=darwin/amd64 ;;
    Linux/x86_64) target=linux/amd64 ;;
    Linux/aarch64 | Linux/arm64) target=linux/arm64 ;;
    *) die "unsupported platform $(uname -s)/$(uname -m)" ;;
esac
os=${target%/*}
arch=${target#*/}
version=$(sed -n 's/^version = "\([0-9.]*\)"$/\1/p' herdr-plugin.toml)
revision=$(git rev-parse HEAD)
[ -n "$version" ] || die "cannot read the version from herdr-plugin.toml"
[ -L "$release_root/current" ] || die "no installed relay at $release_root; install the plugin first"
previous=$(readlink "$release_root/current")
case "$previous" in /*) ;; *) previous="$release_root/$previous" ;; esac
final="$release_root/releases/${version}-${revision}-${os}-${arch}"
[ ! -e "$final" ] || die "$(git rev-parse --short HEAD) is already installed ($final); commit your changes first"

if [ "$os" = darwin ]; then
    service="com.herdr-mobile-relay.service"
    plist="$HOME/Library/LaunchAgents/$service.plist"
    [ -f "$plist" ] || die "no LaunchAgent at $plist; run the relay's setup first"
    env_file=${HERDR_RELAY_ENV:-$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:HERDR_RELAY_ENV' "$plist" 2>/dev/null || true)}
    if [ "$(/usr/libexec/PlistBuddy -c 'Print :ProcessType' "$plist" 2>/dev/null || true)" != Interactive ]; then
        echo "deploy-local: warning: $plist has no ProcessType=Interactive; launchd may throttle the relay" >&2
    fi
    restart() { launchctl kickstart -k "gui/$(id -u)/$service"; }
else
    service=herdr-mobile-relay.service
    env_file=${HERDR_RELAY_ENV:-$(systemctl --user show "$service" -p Environment --value | tr ' ' '\n' | sed -n 's/^HERDR_RELAY_ENV=//p')}
    restart() { systemctl --user restart "$service"; }
fi
[ -n "$env_file" ] && [ -f "$env_file" ] || die "cannot find the relay's environment file; set HERDR_RELAY_ENV"
instance=$(set -a; . "$env_file"; printf '%s' "${HERDR_RELAY_INSTANCE_ID:-}")
port=$(set -a; . "$env_file"; printf '%s' "${HERDR_RELAY_PORT:-8375}")
[ -n "$instance" ] || die "$env_file has no HERDR_RELAY_INSTANCE_ID"

if [ "$build_web" = 1 ]; then
    echo "==> Building the phone app"
    bun frontend/scripts/bump-assets.mjs
    bun run --cwd frontend build
    bun frontend/scripts/release.mjs
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/herdr-relay-deploy.XXXXXX")
trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT
echo "==> Packaging $version ($(git rev-parse --short HEAD)) for $target"
HERDR_RELEASE_TARGETS=$target scripts/package-release.sh "$version" "$revision" "$work/dist" >/dev/null
stage="$work/stage"
mkdir -m 700 "$stage"
tar -xzf "$work/dist/${binary}_${version}_${os}_${arch}.tar.gz" -C "$stage"
"$stage/$binary" verify-release --target "$target" "$stage" >/dev/null

echo "==> Installing $final"
mv "$stage" "$final"
"$final/$binary" seal-release "$final"
"$final/$binary" prune-releases "$release_root" "$final" "$previous"
"$final/$binary" activate-release "$release_root" "$final"
restart

web_hash=$(sed -n 's/^[[:space:]]*"web_hash":[[:space:]]*"\([^"]*\)".*/\1/p' "$final/release-manifest.json" | head -1)
echo "==> Waiting for the relay to report the new release (first inventory can take a while)"
for _ in $(seq 1 180); do
    health=$(curl -sS --max-time 2 "http://127.0.0.1:$port/readyz" 2>/dev/null || true)
    if [ -n "$health" ] && printf '%s\n' "$health" | "$final/$binary" verify-readiness "$instance" "$version" "$revision" "$web_hash" 2>/dev/null; then
        echo "==> Ready: $version $(git rev-parse --short HEAD) on 127.0.0.1:$port"
        [ "$build_web" = 0 ] || echo "    web/ was rebuilt; commit it."
        exit 0
    fi
    sleep 1
done

echo "deploy-local: the new release never became ready; reactivating $previous" >&2
"$previous/$binary" activate-release "$release_root" "$previous"
restart
exit 1
