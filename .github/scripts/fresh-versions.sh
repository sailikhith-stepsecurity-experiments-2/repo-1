#!/usr/bin/env bash
# SR-CI-12.2 / 12.3 e2e: requests recently published versions of several
# packages through secure-registry, so the job summary has more than five
# held and blocked rows. For each package whose dist-tag version is younger
# than MAX_AGE_HOURS (default 48): metadata through secure-registry (held in
# enforce mode) and the tarball (blocked in enforce mode). Also requests the
# known-compromised canary tarball. Never fails: the post step is what's checked.
set -uo pipefail
upstream=https://registry.npmjs.org/
registry=$(npm config get registry)
max_h=${MAX_AGE_HOURS:-48}
echo "registry: $registry, max age ${max_h}h"
cd "$RUNNER_TEMP"

count=0
for spec in typescript:next react:canary react-dom:canary scheduler:canary react-is:canary \
  next:canary @typescript-eslint/parser:canary @typescript-eslint/utils:canary \
  @typescript-eslint/types:canary @typescript-eslint/eslint-plugin:canary \
  @typescript-eslint/scope-manager:canary playwright:next @playwright/test:next \
  playwright-core:next @types/node:latest; do
  pkg=${spec%:*}
  tag=${spec##*:}
  ver=$(npm view "$pkg" "dist-tags.$tag" --registry="$upstream" 2>/dev/null)
  [ -n "$ver" ] || { echo "skip $pkg: no $tag tag"; continue; }
  published=$(npm view "$pkg" "time[$ver]" --registry="$upstream" 2>/dev/null)
  age_h=$(node -e 'console.log(Math.floor((Date.now() - Date.parse(process.argv[1])) / 3600000))' "$published")
  if [ "$age_h" -ge "$max_h" ]; then
    echo "skip $pkg@$ver: ${age_h}h old"
    continue
  fi
  name=${pkg##*/}
  meta_rc=0
  npm view "$pkg@$ver" version >/dev/null 2>&1 || meta_rc=$?
  tar_rc=0
  npm pack "${registry}${pkg}/-/${name}-${ver}.tgz" --dry-run >/dev/null 2>&1 || tar_rc=$?
  echo "$pkg@$ver (${age_h}h old): metadata exit $meta_rc, tarball exit $tar_rc"
  count=$((count + 1))
done

canary_rc=0
npm pack "${registry}@harden-runner-canary/basic-npm-package/-/basic-npm-package-1.5.0.tgz" --dry-run >/dev/null 2>&1 || canary_rc=$?
echo "@harden-runner-canary/basic-npm-package@1.5.0: tarball exit $canary_rc"

echo "::notice title=${GITHUB_JOB:-fresh}::$count fresh versions requested (under ${max_h}h)"
[ "$count" -gt 5 ] || echo "::warning title=${GITHUB_JOB:-fresh}::only $count fresh versions; the 5-row cap may not show"
