#!/bin/sh
# Fetch seeds into this instance and put each one where its kind belongs.
# seedbank fetch only downloads. This script chooses the directory.
# A seed.json does not say where it goes, and it is never run from here.
#
# Names to plant are in scripts/seed-list, one catalog name per line.
# This instance can name more in ~/wizard/config/instance.json:
# "seeds": ["owner/name", ...].
# A bundle is not placed itself; each member is planted the same way.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WIZARD_HOME="${WIZARD_HOME:-$HOME/wizard}"
SEEDBANK="${SEEDBANK:-$(cd "$SCRIPT_DIR/../../seedbank" && pwd)/seedbank}"
INSTANCE="$WIZARD_HOME/config/instance.json"
SEED_LIST="$SCRIPT_DIR/seed-list"

if [ ! -x "$SEEDBANK" ]; then
	echo "error: seedbank not found at $SEEDBANK" >&2
	exit 1
fi
if [ ! -f "$SEED_LIST" ]; then
	echo "error: seed list not found at $SEED_LIST" >&2
	exit 1
fi

mkdir -p "$WIZARD_HOME/seeds"

planted=""
work=""
cleanup() {
	if [ -n "$work" ]; then
		rm -rf "$work"
	fi
}
trap cleanup EXIT

instance_seeds() {
	if [ ! -f "$INSTANCE" ]; then
		return 0
	fi
	python3 -c '
import json, sys
doc = json.load(open(sys.argv[1]))
seeds = doc.get("seeds") or []
if isinstance(seeds, str):
    seeds = seeds.split()
for seed in seeds:
    if isinstance(seed, str) and seed.strip():
        print(seed.strip())
' "$INSTANCE"
}

# Print: name, kind, admin (yes|no), then one member per line.
describe_seed() {
	python3 -c '
import json, sys
spec, path = sys.argv[1], sys.argv[2]
doc = json.load(open(path))
name = doc.get("name") or ""
if not name:
    body = spec.split("@", 1)[0]
    if body.count("/") == 1 and "." not in body.split("/", 1)[0]:
        name = body.split("/", 1)[1]
    elif "//" in body:
        name = body.split("//", 1)[1].strip("/").split("/")[-1]
    else:
        name = body.strip("/").split("/")[-1]
kind = doc.get("kind") or ""
admin = "yes" if "admin" in (doc.get("permissions") or []) else "no"
print(name)
print(kind)
print(admin)
for member in doc.get("members") or []:
    if isinstance(member, str) and member.strip():
        print(member.strip())
' "$1" "$2"
}

replace_tree() {
	_src="$1"
	_dst="$2"
	rm -rf "$_dst"
	mkdir -p "$(dirname "$_dst")"
	cp -R "$_src" "$_dst"
}

plant_spec() {
	_spec="$1"
	case " $planted " in
	*" $_spec "*) return 0 ;;
	esac
	planted="$planted $_spec"

	work="$(mktemp -d)"
	"$SEEDBANK" fetch "$_spec" "$work/seed"

	_meta="$(describe_seed "$_spec" "$work/seed/seed.json")" || exit 1
	_name="$(printf '%s\n' "$_meta" | sed -n '1p')"
	_kind="$(printf '%s\n' "$_meta" | sed -n '2p')"
	_admin="$(printf '%s\n' "$_meta" | sed -n '3p')"
	_members="$(printf '%s\n' "$_meta" | sed -n '4,$p')"

	case "$_name" in
	""|*/*|.*|..)
		echo "error: $_spec has no usable name ($_name)" >&2
		exit 1
		;;
	esac

	_lib="$WIZARD_HOME/seeds/$_name"
	replace_tree "$work/seed" "$_lib"
	rm -rf "$work"
	work=""

	case "$_kind" in
	app|game)
		_dest="$WIZARD_HOME/app/$_name"
		if [ -d "$_lib/ui" ]; then
			replace_tree "$_lib/ui" "$_dest"
		else
			replace_tree "$_lib" "$_dest"
		fi
		echo "planted $_kind $_name -> $_dest"
		;;
	bundle)
		echo "planted bundle $_name -> $_lib"
		;;
	*)
		echo "planted $_kind $_name -> $_lib"
		;;
	esac

	if [ "$_admin" = yes ]; then
		echo "admin: $_name was fetched only; run it yourself, following $_lib/SKILL.md"
	fi

	if [ -n "$_members" ]; then
		for _member in $_members; do
			plant_spec "$_member"
		done
	fi
}

while IFS= read -r _seed || [ -n "$_seed" ]; do
	case "$_seed" in
	""|\#*) continue ;;
	esac
	plant_spec "$_seed"
done < "$SEED_LIST"

for _seed in $(instance_seeds); do
	plant_spec "$_seed"
done
