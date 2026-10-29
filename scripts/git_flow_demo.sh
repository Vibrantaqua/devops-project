#!/usr/bin/env bash
# Creates a deliberate merge conflict on VERSION so you can resolve it and screenshot the process.
# Run from the repo root after the first commit, with branches main and dev already pushed.
set -euo pipefail

git checkout dev
git checkout -b feature/bump-a
echo "1.1.0" > VERSION && git commit -am "feat: bump version to 1.1.0"

git checkout dev
git checkout -b feature/bump-b
echo "1.2.0" > VERSION && git commit -am "feat: bump version to 1.2.0"

git checkout dev
git merge --no-ff feature/bump-a -m "Merge feature/bump-a into dev"
echo ">>> Merging feature/bump-b now. A conflict is EXPECTED."
git merge --no-ff feature/bump-b -m "Merge feature/bump-b into dev" || true

cat <<'MSG'

Conflict created. To resolve:
  1. git status                      (screenshot)
  2. edit VERSION, remove <<<<<<< ======= >>>>>>> markers, keep the value you want
  3. git add VERSION && git commit   (screenshot of the merge commit)
  4. git push origin dev
MSG
