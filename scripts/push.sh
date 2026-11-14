#!/usr/bin/env bash
# Push main to GitHub via ssh.github.com:443.
# github.com:443 is blocked in this WSL2 network; SSH over 443 works.
# Requires the write deploy key ~/.ssh/mooncalc_deploy (registered on the repo).
set -euo pipefail
cd "$(dirname "$0")/.."
GIT_SSH_COMMAND="ssh -i $HOME/.ssh/mooncalc_deploy -p 443 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
  git push ssh://git@ssh.github.com:443/buguoshixc/mooncalc.git main
# git fetch is blocked too; sync the tracking ref from the pushed HEAD.
git update-ref refs/remotes/origin/main "$(git rev-parse main)"