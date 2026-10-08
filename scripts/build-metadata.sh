#!/bin/bash
set -euo pipefail

if [[ "$GITHUB_REF" == refs/tags/* ]]; then
  tag=${GITHUB_REF#refs/tags/}
else
  tag=$(git describe --tags --abbrev=0)
fi

printf 'APP_VERSION=%s\n' "${tag#v}"
printf 'APP_BUILD=%s.%s\n' "$GITHUB_RUN_NUMBER" "$GITHUB_RUN_ATTEMPT"
printf 'APP_COMMIT=%s\n' "$(git rev-parse HEAD)"
