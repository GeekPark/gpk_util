#!/bin/bash

export_filename="$(date +%F)-$RANDOM.psql.xz"
remote_path="/tmp/$export_filename"
local_path="/tmp/$export_filename"

ask_db() {
	echo Choose which db to export: >&2
	select option in $DBS; do
		if [ ! -z $option ]; then
			echo $option
			return
		fi
		echo Invalid choice, choose again >&2
	done
}

get_conf() {
	echo Loading config
	[ -f ~/.gpk_db_conf ] && source ~/.gpk_db_conf
	[ -z "$PG_HOST" -o -z "$PG_USER" -o -z "$PG_PASSWORD" ] && {
		echo Please specify PG_HOST/PG_USER/PG_PASSWORD in ~/.gpk_db_conf
		exit -1
	}
	[ -z "$DBS" -o -z "$ssh_name" ] && {
		echo Please specify DBS/ssh_name in ~/.gpk_db_conf
		exit -1
	}
	echo PG_HOST=$PG_HOST
	echo PG_USER=$PG_USER
}


dump_db() {
	echo Dumping remote database to $ssh_name:$remote_path
	echo Please wait patiently, DO NOT interrupt the script
	ssh $ssh_name /bin/bash >/dev/null << EOF
		export PGPASSWORD="$PG_PASSWORD"
		pg_dump --no-acl --no-owner -U $PG_USER -h $PG_HOST "$1" | \
			xz > "$remote_path"
EOF
	[ $? -eq 0 ] || {
		echo Failed executing command on the server, check your ssh config
	}
}

rm_remote_dump() {
	echo Removing remote dump
	ssh $ssh_name /bin/bash >/dev/null << EOF
		rm -f "$remote_path"
EOF
}

rm_local_dump() {
	read -p "Do you want to delete local dump ($local_path) [y/N]? " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy] ]]; then
		rm -f "$local_path"
	fi
}

pull_back() {
	echo Pulling db dump back to local machine
	scp "$ssh_name:$remote_path" "$local_path"
	[ -f "$local_path" ] || {
		echo Failed to pull remote file, clearing up
		rm_remote_dump
		exit -1
	}
	echo DB pulled to "$local_path"
}

ask_import_db() {
	read -e -p "Enter local DB name (default: ${db}_development)? " local_db
	local_db=${local_db:-${db}_development}
}

ask_import() {
	read -p "Do you want to import to local db [y/N]? " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy] ]]; then
		ask_import_db
		return 0
	fi
	return 1
}

import() {
	[ -z "$local_db" ] && {
		echo Invalid database name: $local_db.
	}
	xzcat $local_path | psql "$local_db" > /dev/null
	[ $? -eq 0 ] && echo "Import successful."
}

local_db_found() {
	for file in $(ls /tmp/*.psql.xz 2>/dev/null) ; do
		read -p "Local dump found at $file, choose this one (y/N)? " -n1 -r
		echo
		if [[ $REPLY =~ ^[Yy] ]]; then
			local_path="$file"
			return 0
		fi
	done
	return 1
}

main() {
	get_conf
	if ! local_db_found; then
		db=$(ask_db)
		dump_db "$db"
		pull_back
		rm_remote_dump
	fi

	if ask_import; then
		import
	fi
	rm_local_dump
}

main

