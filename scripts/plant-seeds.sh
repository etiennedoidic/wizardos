#!/bin/sh
# Pseudo: plant the seeds this instance requires. Fetch is not implemented.

set -eu

SEEDBANK_REMOTE="git@github.com:etiennedoidic/seedbank.git"
INSTANCE_SEED_DIR="${WIZARD_HOME:?}/seeds"

instance_seed_config='
transport-controls component seed_id_transport_controls
echo-args tool seed_id_echo_args
task-list app seed_id_task_list
'

fetch_seed_from_seedbank() {
	seed_alias="$1"
	seed_kind="$2"
	seed_id="$3"
	echo "fetch $seed_kind $seed_alias ($seed_id) from $SEEDBANK_REMOTE into $INSTANCE_SEED_DIR/$seed_id"
}

printf '%s\n' "$instance_seed_config" | while IFS=' ' read -r seed_alias seed_kind seed_id; do
	[ -n "$seed_alias" ] || continue
	fetch_seed_from_seedbank "$seed_alias" "$seed_kind" "$seed_id"
done
