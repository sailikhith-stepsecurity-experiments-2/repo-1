#!/usr/bin/env bash
# Checks whether a package manager's installs go through secure-registry
# after the Harden-Runner pre step (SR-CI-14).
#
#   check-pm.sh <pm> <fresh|lockfile> <covered|uncovered>
#
#   pm        npm | pnpm | yarn-classic | yarn-berry | bun
#   fresh     empty project: add ms@2.1.3 (must work), then add the
#             typescript@next build, which a 2-day cooldown hides
#   lockfile  lockfile generated against registry.npmjs.org that pins the
#             typescript@next build; frozen install with an empty cache
#
# The probe version is under 2 days old, so secure-registry refuses it. An
# install that fails means the package manager went through secure-registry
# ("covered"); one that succeeds means it fetched from npmjs ("uncovered").
# The expectation is checked and the observed result is always printed.
set -uo pipefail

pm=$1
scenario=$2
expect=$3
npmjs=https://registry.npmjs.org/

fail() {
  echo "::error title=$pm $scenario (${RUNNER_OS:-})::$1"
  exit 1
}

next=$(npm view typescript dist-tags.next --registry="$npmjs")
published=$(npm view typescript "time[$next]" --registry="$npmjs")
age_h=$(node -e 'console.log(Math.floor((Date.now() - Date.parse(process.argv[1])) / 3600000))' "$published")
echo "probe: typescript@$next, published ${age_h}h ago"
if [ "$age_h" -ge 48 ]; then
  echo "::warning title=$pm $scenario::typescript@next is ${age_h}h old, outside the 2-day cooldown; probe skipped"
  exit 0
fi
host=$(npm config get registry | cut -d/ -f3)
echo "npm registry host: $host"

# pm_run <dir> <registry-override|""> <args...>
# Runs the package manager in <dir> with a cache private to <dir>. A
# registry override is used only to generate the npmjs lockfile.
pm_run() {
  local dir=$1 reg=$2
  shift 2
  local cache="$dir/.pm-cache"
  (
    cd "$dir" || exit 1
    case "$pm" in
      npm)
        npm "$@" --cache "$cache" --no-audit --no-fund --loglevel=http ${reg:+--registry="$reg"}
        ;;
      pnpm)
        pnpm "$@" --store-dir "$cache/store" --cache-dir "$cache/meta" ${reg:+--registry="$reg"}
        ;;
      yarn-classic)
        yarn "$@" --cache-folder "$cache" --verbose ${reg:+--registry "$reg"}
        ;;
      yarn-berry)
        # Yarn 4 has its own release-age gate ("quarantined"); turn it off so
        # only secure-registry can refuse the probe.
        local server=()
        [ -n "$reg" ] && server=("YARN_NPM_REGISTRY_SERVER=${reg%/}")
        env YARN_CACHE_FOLDER="$cache" YARN_ENABLE_GLOBAL_CACHE=false \
          YARN_ENABLE_MIRROR=false YARN_ENABLE_TELEMETRY=false \
          YARN_NPM_MINIMAL_AGE_GATE=0 \
          ${server[@]+"${server[@]}"} \
          yarn "$@"
        ;;
      bun)
        BUN_INSTALL_CACHE_DIR="$cache" bun "$@" --verbose ${reg:+--registry "$reg"}
        ;;
      *) echo "unknown pm $pm"; exit 2 ;;
    esac
  )
}

new_project() {
  local dir=$1
  rm -rf "$dir"
  mkdir -p "$dir"
  echo '{"name":"srci14-probe","version":"1.0.0","private":true}' >"$dir/package.json"
  if [ "$pm" = yarn-berry ]; then
    echo '{"name":"srci14-probe","version":"1.0.0","private":true,"packageManager":"yarn@4.18.1"}' >"$dir/package.json"
    printf 'nodeLinker: node-modules\n' >"$dir/.yarnrc.yml"
    touch "$dir/yarn.lock"
  fi
}

add_args() {
  case "$pm" in
    npm) echo install ;;
    *) echo add ;;
  esac
}

frozen_args() {
  case "$pm" in
    npm) echo ci ;;
    pnpm) echo install --frozen-lockfile ;;
    yarn-classic) echo install --frozen-lockfile ;;
    yarn-berry) echo install --immutable ;;
    bun) echo install --frozen-lockfile ;;
  esac
}

lockfile_name() {
  case "$pm" in
    npm) echo package-lock.json ;;
    pnpm) echo pnpm-lock.yaml ;;
    yarn-*) echo yarn.lock ;;
    bun) echo bun.lock ;;
  esac
}

show_registry_config() {
  case "$pm" in
    pnpm) echo "pnpm registry: $(cd "$1" && pnpm config get registry)" ;;
    yarn-classic) echo "yarn registry: $(cd "$1" && yarn config get registry)" ;;
    yarn-berry) echo "yarn npmRegistryServer: $(cd "$1" && yarn config get npmRegistryServer)" ;;
  esac
}

log="$RUNNER_TEMP/$pm-$scenario.log"
base="$RUNNER_TEMP/srci14-$pm-$scenario"
export YARN_ENABLE_IMMUTABLE_INSTALLS=false

case "$scenario" in
  fresh)
    new_project "$base"
    show_registry_config "$base"
    echo "--- $pm $(add_args) ms@2.1.3"
    pm_run "$base" "" $(add_args) ms@2.1.3 >"$log" 2>&1
    rc=$?
    tail -15 "$log"
    [ "$rc" -eq 0 ] || fail "installing ms@2.1.3 failed (exit $rc): the package manager is broken by the setup"
    echo "--- $pm $(add_args) typescript@$next"
    pm_run "$base" "" $(add_args) "typescript@$next" >>"$log" 2>&1
    probe_rc=$?
    ;;

  lockfile)
    gen="$base-gen"
    new_project "$gen"
    echo "--- generating $(lockfile_name) against $npmjs"
    pm_run "$gen" "$npmjs" $(add_args) ms@2.1.3 "typescript@$next" >"$log" 2>&1 \
      || { tail -30 "$log"; fail "could not generate the npmjs lockfile"; }
    lock=$(lockfile_name)
    echo "--- $lock entries for typescript:"
    grep -n -A4 "typescript" "$gen/$lock" | head -12
    new_project "$base"
    cp "$gen/package.json" "$gen/$lock" "$base/"
    show_registry_config "$base"
    echo "--- $pm $(frozen_args) (empty cache)"
    pm_run "$base" "" $(frozen_args) >>"$log" 2>&1
    probe_rc=$?
    ;;

  *) fail "unknown scenario $scenario" ;;
esac

echo "--- last lines of the probe install (exit $probe_rc)"
tail -25 "$log" | sed -E 's/(_authToken=)[^ ]*/\1<redacted>/g'
mentions=$(grep -c "$host" "$log" || true)
echo "log lines naming $host: $mentions"

if [ "$probe_rc" -eq 0 ]; then observed=uncovered; else observed=covered; fi
msg="observed $observed (probe install exit $probe_rc, typescript@$next ${age_h}h old), expected $expect"
[ "$observed" = "$expect" ] || fail "$msg"
echo "::notice title=$pm $scenario ($RUNNER_OS)::$msg"
