#!/usr/bin/env bash
# Checks how npm is configured after the Harden-Runner pre step.
#
#   check-npm.sh secure              npm uses secure-registry for every fetch
#   check-npm.sh default             npm is untouched
#   check-npm.sh cooldown blocked    a typescript@next build (under 2 days old) is hidden
#   check-npm.sh cooldown allowed    the same build is served (audit mode)
#
# EXPECT_OMIT_RESOLVED=true additionally requires omit-lockfile-registry-resolved.
set -euo pipefail

fail() {
  echo "::error title=${GITHUB_JOB:-check}::$1"
  exit 1
}

file_mode() {
  case "$(uname -s)" in
    Darwin) stat -f %Lp "$1" ;;
    *) stat -c %a "$1" ;;
  esac
}

registry=$(npm config get registry)
userconfig=${NPM_CONFIG_USERCONFIG:-${npm_config_userconfig:-}}
echo "npm $(npm --version), node $(node --version), $(uname -s)"
echo "registry:   $registry"
echo "userconfig: ${userconfig:-<unset>}"

case "$1" in
  secure)
    case "$registry" in
      https://*.registry-int.stepsecurity.io/javascript/) ;;
      *) fail "npm registry is $registry, expected a registry-int.stepsecurity.io host" ;;
    esac
    { [ -n "$userconfig" ] && [ -f "$userconfig" ]; } || fail "NPM_CONFIG_USERCONFIG does not point at a file"
    if [ "${RUNNER_OS:-}" != "Windows" ]; then
      mode=$(file_mode "$userconfig")
      echo "mode:       $mode"
      [ "$mode" = 600 ] || fail "$userconfig has mode $mode, expected 600"
    fi
    echo "--- $userconfig (token redacted)"
    sed -E 's/(_authToken=).*/\1<redacted>/' "$userconfig"
    echo "---"
    if [ "${EXPECT_OMIT_RESOLVED:-}" = true ]; then
      grep -qx 'omit-lockfile-registry-resolved=true' "$userconfig" \
        || fail "omit-lockfile-registry-resolved=true is missing"
    fi

    host=$(echo "$registry" | cut -d/ -f3)
    log="$RUNNER_TEMP/npm-ci.log"
    npm ci --no-audit --no-fund --loglevel=http 2>&1 | tee "$log"
    fetches=$(grep -c 'npm http fetch' "$log" || true)
    outside=$(grep 'npm http fetch' "$log" | grep -v " https://$host/" || true)
    [ -z "$outside" ] || fail "npm fetched outside secure-registry: $outside"
    [ "$fetches" -gt 0 ] || fail "npm ci made no registry fetches"
    echo "::notice title=${GITHUB_JOB:-check}::npm ci made $fetches fetches, all through $host"
    ;;

  default)
    [ "$registry" = "https://registry.npmjs.org/" ] || fail "npm registry is $registry, expected the default"
    [ -z "$userconfig" ] || fail "NPM_CONFIG_USERCONFIG is set to $userconfig"
    npm ci --no-audit --no-fund
    echo "::notice title=${GITHUB_JOB:-check}::npm is on the default registry"
    ;;

  cooldown)
    expect=$2
    upstream=https://registry.npmjs.org/
    next=$(npm view typescript dist-tags.next --registry="$upstream")
    published=$(npm view typescript "time[$next]" --registry="$upstream")
    age_h=$(( ($(date -u +%s) - $(date -u -d "$published" +%s)) / 3600 ))
    echo "typescript@$next was published $published (${age_h}h ago)"
    if [ "$age_h" -ge 48 ]; then
      echo "::warning title=cooldown probe::typescript@next is ${age_h}h old, outside the 2-day cooldown; probe skipped"
      exit 0
    fi

    rc=0
    got=$(npm view "typescript@$next" version 2>"$RUNNER_TEMP/view.err") || rc=$?
    echo "secure-registry answered: exit $rc, version '${got}'"
    tail -5 "$RUNNER_TEMP/view.err" || true
    case "$expect" in
      blocked)
        { [ "$rc" -ne 0 ] || [ "$got" != "$next" ]; } \
          || fail "typescript@$next (${age_h}h old) was served; the 2-day cooldown should hide it"
        echo "::notice title=cooldown probe::typescript@$next (${age_h}h old) was withheld as expected"
        ;;
      allowed)
        [ "$rc" -eq 0 ] && [ "$got" = "$next" ] \
          || fail "typescript@$next was not served; audit mode should only report it"
        echo "::notice title=cooldown probe::typescript@$next (${age_h}h old) was served, as audit mode should"
        ;;
      *) fail "unknown cooldown expectation '$expect'" ;;
    esac
    ;;

  *) fail "unknown check '$1'" ;;
esac
