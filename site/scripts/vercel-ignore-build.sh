#!/bin/bash
# Vercel "Ignored Build Step" for the site project (Root Directory: site/).
#
# The site reads ../CHANGELOG.md at build time for its changelog page, so a
# plain "did anything under Root Directory change" check isn't enough - this
# also has to watch CHANGELOG.md even though it lives outside site/.
#
# Vercel's convention here is inverted from what you'd expect: exit 1 means
# "proceed with the build", exit 0 means "skip it". See
# https://vercel.com/kb/guide/how-do-i-use-the-ignored-build-step-field-on-vercel
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# VERCEL_GIT_PREVIOUS_SHA is one of Vercel's system environment variables:
# https://vercel.com/docs/environment-variables/system-environment-variables
if git diff --quiet "$VERCEL_GIT_PREVIOUS_SHA" HEAD -- site/ CHANGELOG.md; then
  echo "No changes to site/ or CHANGELOG.md - skipping build"
  exit 0
else
  echo "Relevant changes detected - proceeding with build"
  exit 1
fi
