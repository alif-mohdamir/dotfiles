#!/bin/bash

host=
config=$HOME/.config/ce-sync/config
# Read as data: the config is shell that ce-sync sources, and a title lookup must not run it
if [[ -r $config ]]; then
	while IFS= read -r line || [[ -n $line ]]; do
		[[ $line =~ ^[[:space:]]*CE_SYNC_HOST=(.*)$ ]] && host=${BASH_REMATCH[1]}
	done <"$config"
fi
[[ $host =~ ^\"(.*)\"$ || $host =~ ^\'(.*)\'$ ]] && host=${BASH_REMATCH[1]}
printf '%s %s\n' "${host:-$HOSTNAME}" "${PEON_CWD##*/}"
