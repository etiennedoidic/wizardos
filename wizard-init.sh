#!/bin/sh
# wizard-init.sh — first-time owner install of WizardOS on this Mac.
# Detects an existing owner instance, asks public/private/both, then:
#   1. Wizard directory contract (this repo's layout script)
#   2. Plant requisite seeds from seedbank
#   3. friendly-hosting owner-init (machine + network + tenancy)
#   4. Funnel of the public tree if they asked for public or both
#
# Usage: ./wizard-init.sh
# Run as the owner unix account, not as root.

set -eu
set -o pipefail 2>/dev/null || true

ROOT="$(cd "$(dirname "$0")" && pwd)"
FH="$ROOT/friendly-hosting"
LAYOUT="$ROOT/scripts/wizard-layout.sh"
PLANT="$ROOT/scripts/plant-seeds.sh"

if [ "$(id -u)" -eq 0 ]; then
	echo "error: run wizard-init.sh as the owner account, not sudo. The script will sudo hosting steps itself." >&2
	exit 1
fi

if [ "$(uname -s)" != "Darwin" ]; then
	echo "error: WizardOS init currently targets macOS (friendly-hosting)." >&2
	exit 1
fi

if [ ! -x "$FH/scripts/owner-init.sh" ]; then
	echo "error: friendly-hosting scripts missing under $FH/scripts" >&2
	exit 1
fi

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH

WIZARD_HOME="${WIZARD_HOME:-$HOME/wizard}"
FH_PUBLIC_DIR="${FH_PUBLIC_DIR:-$HOME/www}"
FH_PRIVATE_DIR="${FH_PRIVATE_DIR:-$WIZARD_HOME/app}"
export WIZARD_HOME FH_PUBLIC_DIR FH_PRIVATE_DIR
FH_FOR_USER="$(id -un)"
export FH_FOR_USER

echo "WizardOS owner init"
echo "  unix user:    $FH_FOR_USER"
echo "  wizard home:  $WIZARD_HOME"
echo "  private app:  $FH_PRIVATE_DIR"
echo "  public www:   $FH_PUBLIC_DIR"
echo

# --- existing owner instance on this device --------------------------------
EXISTING=""
EXISTING_USER=""
for _inst in /Users/*/wizard/config/instance.json; do
	[ -f "$_inst" ] || continue
	_role="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("role") or "")' "$_inst" 2>/dev/null || true)"
	[ "$_role" = "owner" ] || continue
	_user="$(printf '%s\n' "$_inst" | awk -F/ '{print $3}')"
	EXISTING="$_inst"
	EXISTING_USER="$_user"
	if [ "$_user" = "$FH_FOR_USER" ]; then
		break
	fi
done

if [ -n "$EXISTING" ] && [ "$EXISTING_USER" != "$FH_FOR_USER" ]; then
	echo "This Mac already has a WizardOS owner instance:"
	echo "  $EXISTING"
	echo "Log in as $EXISTING_USER to manage it. Refusing to create a second owner."
	exit 1
fi

if [ -n "$EXISTING" ] && [ "$EXISTING_USER" = "$FH_FOR_USER" ]; then
	echo "Found an existing WizardOS owner instance:"
	echo "  $EXISTING"
	python3 -m json.tool <"$EXISTING" 2>/dev/null || cat "$EXISTING"
	echo
	printf 'Overwrite layout fixtures and continue with hosting? [y/N]: '
	IFS= read -r _ans || _ans=""
	case "$_ans" in
	y|Y|yes|YES) FORCE_LAYOUT=1 ;;
	*) echo "stopped."; exit 0 ;;
	esac
else
	FORCE_LAYOUT=""
fi

# --- intake ----------------------------------------------------------------
echo "Are you planning on hosting any pages on the internet publicly,"
echo "only privately (people you share the Tailscale node with), or both?"
echo "  1) private"
echo "  2) public"
echo "  3) both"
printf 'choice [3]: '
IFS= read -r _choice || _choice=""
case "${_choice:-3}" in
1|private) FH_PUBLISH_MODE="private" ;;
2|public) FH_PUBLISH_MODE="public" ;;
3|both|"") FH_PUBLISH_MODE="both" ;;
*) echo "error: choose 1, 2, or 3" >&2; exit 2 ;;
esac
export FH_PUBLISH_MODE
echo "hosting: $FH_PUBLISH_MODE"
echo

printf 'Is this a headless Mac Mini that should stay awake after you hang up? [y/N]: '
IFS= read -r _mini || _mini=""
RUN_PREP=""
case "$_mini" in
y|Y|yes|YES) RUN_PREP=1 ;;
esac

if [ -z "${FH_HOSTNAME:-}" ]; then
	printf 'Hostname for this machine [mini]: '
	IFS= read -r FH_HOSTNAME || FH_HOSTNAME=""
	FH_HOSTNAME="${FH_HOSTNAME:-mini}"
fi
export FH_HOSTNAME

if [ -z "${TS_API_TOKEN:-}" ]; then
	echo
	echo "Tailscale API access token (Keys page, 90-day max). Empty = browser login;"
	echo "ACL write and share-link creation will be skipped."
	printf 'API token: '
	IFS= read -r TS_API_TOKEN || TS_API_TOKEN=""
	export TS_API_TOKEN
	export FH_TOKEN_DONE=1
fi

# --- 1. application layout (this product) ----------------------------------
echo
echo "==> WizardOS layout"
if [ -n "$FORCE_LAYOUT" ]; then
	"$LAYOUT" --role owner --force
else
	"$LAYOUT" --role owner
fi

# --- 2. plant seeds from seedbank ------------------------------------------
echo
echo "==> plant seeds"
"$PLANT"

# --- 3. machine + network (friendly-hosting) --------------------------------
if [ -n "$RUN_PREP" ]; then
	echo
	echo "==> prep-mini (sleep off, SSH on, FileVault warning)"
	sudo "$FH/scripts/prep-mini.sh"
fi

HOSTING_READY=""
if [ -f "$HOME/.friendly-hosting/ready" ]; then
	HOSTING_READY=1
	echo
	echo "friendly-hosting already marked ready at $HOME/.friendly-hosting/ready"
	echo "Re-running owner-init to point Serve at $FH_PRIVATE_DIR (ACL left alone)."
	export FH_SKIP_ACL=1
fi

echo
echo "==> friendly-hosting owner-init"
if [ -z "${FH_SKIP_ACL:-}" ]; then
	echo "This may replace the tailnet ACL so shared users can only reach tcp 443 and 22 on this Mac."
fi
export FH_SKIP_RENTER=1
if [ -n "$HOSTING_READY" ]; then
	export FH_NONINTERACTIVE=1
fi

sudo env \
	TS_API_TOKEN="${TS_API_TOKEN:-}" \
	FH_TOKEN_DONE="${FH_TOKEN_DONE:-}" \
	FH_HOSTNAME="$FH_HOSTNAME" \
	FH_FOR_USER="$FH_FOR_USER" \
	FH_PRIVATE_DIR="$FH_PRIVATE_DIR" \
	FH_PUBLIC_DIR="$FH_PUBLIC_DIR" \
	FH_PUBLISH_MODE="$FH_PUBLISH_MODE" \
	FH_SKIP_RENTER="${FH_SKIP_RENTER:-}" \
	FH_SKIP_ACL="${FH_SKIP_ACL:-}" \
	FH_YES="${FH_YES:-}" \
	FH_NONINTERACTIVE="${FH_NONINTERACTIVE:-}" \
	"$FH/scripts/owner-init.sh"

# --- 4. public door --------------------------------------------------------
case "$FH_PUBLISH_MODE" in
public|both)
	echo
	echo "==> public www (Funnel on 8443)"
	sudo env \
		FH_FOR_USER="$FH_FOR_USER" \
		FH_PUBLIC_DIR="$FH_PUBLIC_DIR" \
		"$FH/scripts/enable-public-www.sh" "$FH_FOR_USER"
	echo
	echo "For a real domain later, as this user:"
	echo "  $FH/scripts/setup-cloudflared.sh example.com"
	echo "  or  $FH/scripts/setup-cloudflared.sh example.com=wall"
	;;
private)
	echo
	echo "private only: Funnel was not enabled. Public files can still live in"
	echo "  $FH_PUBLIC_DIR"
	echo "Turn the public door on later with:"
	echo "  sudo $FH/scripts/enable-public-www.sh $FH_FOR_USER"
	;;
esac

echo
echo "WizardOS owner init finished."
echo "  instance: $WIZARD_HOME/config/instance.json"
echo "  docs:     $FH/docs/owner.md  (hosting) and $FH/docs/renter.md (friends)"
echo "Later: real seedbank fetch, Serve --set-path /api, MCP/MLX switches."
