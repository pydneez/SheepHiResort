#!/usr/bin/env bash
# Every res:// file path written in a script, scene or resource must point at a
# file that exists with exactly the same capitals. Windows doesn't care about
# capitals, but exported builds (Linux, Mac, web, Android) do: "grade_S.png"
# for grade_s.png works in the editor and breaks there.
# Paths built from a pattern ("grade_%s.png") must match at least one file.
set -uo pipefail

# Is there an entry in dir named exactly like name (a regex when $3 is set)?
has_entry() {
	local dir="$1" name="$2" regex="${3:-}"
	if [ -n "$regex" ]; then
		ls -a "$dir" 2>/dev/null | grep -qE "^${name}\$"
	else
		ls -a "$dir" 2>/dev/null | grep -qxF "$name"
	fi
}

bad=""
while IFS= read -r ref; do
	path="${ref#res://}"
	dir="."
	IFS='/' read -ra parts <<< "$path"
	ok=1
	for part in "${parts[@]}"; do
		if [[ "$part" == *%* ]]; then
			# A pattern: %s / %d / %02d ... stand for any text.
			re="$(printf '%s' "$part" | sed -E 's/[].[^$*+?(){}|\\]/\\&/g; s/%[0-9]*[sd]/.+/g')"
			has_entry "$dir" "$re" regex || { ok=0; break; }
			break   # nothing after a pattern part can be checked
		fi
		has_entry "$dir" "$part" || { ok=0; break; }
		dir="$dir/$part"
	done
	[ "$ok" -eq 1 ] || bad+="  $ref"$'\n'
done < <(grep -rhoE 'res://[^"'"'"' )]+\.[A-Za-z0-9]+' \
	--include='*.gd' --include='*.tscn' --include='*.tres' --include='*.godot' . | sort -u)

if [ -n "$bad" ]; then
	echo "These res:// paths don't match a file exactly (check the capitals):"
	printf '%s' "$bad"
	echo "::error::Fix the paths listed above"
	exit 1
fi
echo "Every res:// path matches a file exactly."
