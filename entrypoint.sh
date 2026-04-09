#!/bin/sh
set -eu

env_enabled() {
	case "${1:-}" in
		0|false|FALSE|no|NO|off|OFF)
			return 1
			;;
		*)
			return 0
			;;
	esac
}

int_or_default() {
	value="${1:-}"
	fallback="$2"

	case "$value" in
		''|0)
			printf '%s' "$fallback"
			;;
		*[!0-9]*)
			echo "error: invalid integer value: $value" >&2
			exit 1
			;;
		*)
			printf '%s' "$value"
			;;
	esac
}

fix_path_permissions() {
	path="$1"
	if [ ! -e "$path" ]; then
		return 0
	fi

	if [ -d "$path" ]; then
		fix_dir_tree "$path"
		return 0
	fi

	if ! chmod u+rw "$path" 2>/dev/null; then
		echo "warning: failed to normalize permissions on $path" >&2
	fi
}

fix_dir_tree() {
	dir="$1"

	# Ensure this directory can be traversed before processing children.
	if ! chmod u+rwx "$dir" 2>/dev/null; then
		echo "warning: failed to normalize directory permissions on $dir" >&2
		return 0
	fi

	for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
		[ -e "$entry" ] || continue

		# Skip symlinks to avoid loops and cross-tree permission edits.
		if [ -h "$entry" ]; then
			continue
		fi

		if [ -d "$entry" ]; then
			fix_dir_tree "$entry"
			continue
		fi

		if ! chmod u+rw "$entry" 2>/dev/null; then
			echo "warning: failed to normalize file permissions on $entry" >&2
		fi
	done
}

# Default the TZ environment variable to UTC.
TZ=${TZ:-UTC}
export TZ

# Use Luanti's plain terminal mode by default in panel environments.
# Set LUANTI_TERMINAL_PLAIN=0 to force full ncurses UI.
LUANTI_TERMINAL_PLAIN=${LUANTI_TERMINAL_PLAIN:-1}
export LUANTI_TERMINAL_PLAIN

# Fix ownership on Luanti data paths at startup (helpful for SFTP uploads).
# Set LUANTI_FIX_PERMS=0 to disable.
LUANTI_FIX_PERMS=${LUANTI_FIX_PERMS:-1}
export LUANTI_FIX_PERMS

# If Pelican creates a server without an allocation it injects SERVER_PORT=0.
# Normalize that to a stable internal-only port so the server can still listen
# on the shared Docker network behind mt-multiserver-proxy.
SERVER_PORT=$(int_or_default "${SERVER_PORT:-}" "${LUANTI_INTERNAL_PORT:-30000}")
export SERVER_PORT

if env_enabled "$LUANTI_FIX_PERMS"; then
	mkdir -p /home/container/.luanti /home/container/.cache/luanti

	# Ensure uploaded files/directories are usable by the current runtime user.
	# This also fixes broken directory mode bits (missing +x) from some uploads.
	for path in \
		/home/container/.luanti \
		/home/container/.cache/luanti \
		/home/container/.minetest \
		/home/container/server.log
	do
		fix_path_permissions "$path"
	done

	if [ "$(id -u)" -eq 0 ]; then
		for path in \
			/home/container/.luanti \
			/home/container/.cache/luanti \
			/home/container/.minetest \
			/home/container/server.log
		do
			if [ -e "$path" ] && ! chown -R container:container "$path" 2>/dev/null; then
				echo "warning: failed to adjust ownership on $path" >&2
			fi
		done
	fi
fi

# Switch to the container's working directory
cd /home/container || exit 1

# Convert all of the "{{VARIABLE}}" parts of the command into the expected shell
# variable format of "${VARIABLE}" before evaluating the string and automatically
# replacing the values.
PARSED=$(echo "$STARTUP" | sed -e 's/{{/${/g' -e 's/}}/}/g')

# Display the command we're running in the output, and then execute it.
echo "container~ $PARSED"

if [ "$(id -u)" -eq 0 ]; then
	exec su-exec container:container sh -c "$PARSED"
fi

exec sh -c "$PARSED"
