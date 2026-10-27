#!/usr/bin/env bash
# Game files must be lowercase with no spaces: exported builds are
# case-sensitive, so "Bell.png" vs "bell.png" or "End summary.png" break there.
set -uo pipefail

bad="$(find assets scene script ui tests -type f ! -name '*.import' ! -name '*.uid' 2>/dev/null \
	| grep -E ' |[A-Z]' || true)"

if [ -n "$bad" ]; then
	echo "These files need lowercase names without spaces (use_underscores_instead.png):"
	echo "$bad" | sed 's/^/  /'
	echo "::error::Rename the files listed above"
	exit 1
fi
echo "All file names are lowercase without spaces."
