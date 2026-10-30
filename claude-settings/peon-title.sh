#!/bin/bash
# peon-ping's notification_title_script on a box: prints the box name, then the base name of $PEON_CWD.
# The box name is CE_SYNC_HOST from the ce-sync config, else the hostname.

host=
config=$HOME/.config/ce-sync/config
# Read as data: the config is shell that ce-sync sources, and a title lookup must not run it
if [[ -r $config ]]; then
	while IFS= read -r line || [[ -n $line ]]; do
		[[ $line =~ ^[[:space:]]*CE_SYNC_HOST=(.*)$ ]] && host=${BASH_REMATCH[1]}
	done <"$config"
fi
[[ $host =~ ^\"(.*)\"$ || $host =~ ^\'(.*)\'$ ]] && host=${BASH_REMATCH[1]}
printf '%s %s\n' "${host:-$(uname -n)}" "${PEON_CWD##*/}"
