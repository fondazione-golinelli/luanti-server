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

if [ "$(id -u)" -eq 0 ] && env_enabled "$LUANTI_FIX_PERMS"; then
	mkdir -p /home/container/.luanti /home/container/.cache/luanti
	if ! chown -R container:container \
		/home/container/.luanti \
		/home/container/.cache/luanti \
		/home/container/server.log 2>/dev/null; then
		echo "warning: failed to adjust ownership on one or more Luanti paths" >&2
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
