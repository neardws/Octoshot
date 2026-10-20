#!/bin/bash

PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
[ -f "$PLIST" ] || exit 0

/usr/libexec/PlistBuddy -c 'Delete :OctoshotGitCommit' "$PLIST" >/dev/null 2>&1 || true
command -v git >/dev/null 2>&1 || exit 0
COMMIT=$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null) || exit 0
STATUS=$(git --no-optional-locks -C "$PROJECT_DIR" status --porcelain 2>/dev/null) || exit 0
if [ -n "$STATUS" ]; then
  COMMIT="${COMMIT}-dirty"
fi

/usr/libexec/PlistBuddy -c "Add :OctoshotGitCommit string $COMMIT" "$PLIST" >/dev/null 2>&1 || true
exit 0
