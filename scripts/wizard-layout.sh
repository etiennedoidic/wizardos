#!/bin/sh
# wizard-layout.sh — WizardOS directory contract on an already-hosted unix user.
# Never: sysadminctl, tailscale up, ACL, Funnel, cloudflared, pmset.
#
# Usage: ./scripts/wizard-layout.sh [--role owner|renter] [--force]
# Env: FH_PUBLIC_DIR (default ~/www), WIZARD_HOME (default ~/wizard)

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROLE="owner"
FORCE=""
while [ $# -gt 0 ]; do
	case "$1" in
	--role)
		ROLE="${2:-}"
		shift 2
		;;
	--force)
		FORCE=1
		shift
		;;
	-h|--help)
		echo "usage: $0 [--role owner|renter] [--force]"
		exit 0
		;;
	*)
		echo "unknown arg: $1" >&2
		exit 2
		;;
	esac
done

case "$ROLE" in
owner|renter) ;;
*) echo "role must be owner or renter" >&2; exit 2 ;;
esac

if [ "$(id -u)" -eq 0 ]; then
	echo "error: run wizard-layout as the unix user who will own ~/wizard, not as root" >&2
	exit 1
fi

WIZARD_HOME="${WIZARD_HOME:-$HOME/wizard}"
PUBLIC_DIR="${FH_PUBLIC_DIR:-$HOME/www}"
INSTANCE="$WIZARD_HOME/config/instance.json"

mkdir -p \
	"$WIZARD_HOME/app" \
	"$WIZARD_HOME/data" \
	"$WIZARD_HOME/seeds" \
	"$WIZARD_HOME/blobs" \
	"$WIZARD_HOME/config" \
	"$PUBLIC_DIR/wall"

copy_tree() {
	_src="$1"
	_dst="$2"
	if [ -n "$FORCE" ] || [ ! -f "$_dst/index.html" ]; then
		mkdir -p "$_dst"
		cp -R "$_src/." "$_dst/"
	fi
}

copy_tree "$ROOT/fixtures/app" "$WIZARD_HOME/app"
copy_tree "$ROOT/fixtures/wall" "$PUBLIC_DIR/wall"

CREATED="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
if [ -f "$INSTANCE" ] && [ -z "$FORCE" ]; then
	# Keep created time if present; refresh paths/role/hosting.
	CREATED="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("created") or "")' "$INSTANCE" 2>/dev/null || true)"
	[ -n "$CREATED" ] || CREATED="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
fi

HOSTING="${FH_PUBLISH_MODE:-}"
python3 - "$INSTANCE" "$ROLE" "$CREATED" "$WIZARD_HOME" "$PUBLIC_DIR" "$HOSTING" <<'PY'
import json, sys
path, role, created, wizard, public, hosting = sys.argv[1:7]
doc = {
    "role": role,
    "created": created,
    "wizardHome": wizard,
    "privateDir": wizard + "/app",
    "publicDir": public,
    "wallDir": public + "/wall",
    "dataDir": wizard + "/data",
    "seedsDir": wizard + "/seeds",
    "blobsDir": wizard + "/blobs",
}
if hosting:
    doc["hosting"] = hosting
with open(path, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY

chmod 700 "$WIZARD_HOME/data" "$WIZARD_HOME/blobs" 2>/dev/null || true

echo "WizardOS layout:"
echo "  $WIZARD_HOME/app      private PWA (friendly-hosting Serve root)"
echo "  $WIZARD_HOME/data     instance data"
echo "  $WIZARD_HOME/seeds    seed library"
echo "  $WIZARD_HOME/blobs    content-addressed blobs"
echo "  $WIZARD_HOME/config   instance.json"
echo "  $PUBLIC_DIR/wall      Wall (public tree that friendly-hosting already owns)"
echo "wrote $INSTANCE"
