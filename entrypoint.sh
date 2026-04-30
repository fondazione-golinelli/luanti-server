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

bootstrap_instance_template() {
	kind="${LUANTI_SERVER_KIND:-standard}"
	template_name="${INSTANCE_TEMPLATE_NAME:-}"
	template_mount="${INSTANCE_TEMPLATE_MOUNT:-/mnt/presets}"
	template_marker="/home/container/.pelican-instance-template"

	if [ "$kind" != "instance" ]; then
		return 0
	fi

	if [ -f "$template_marker" ]; then
		echo "Instance template already bootstrapped."
		return 0
	fi

	if [ -z "$template_name" ]; then
		echo "error: INSTANCE_TEMPLATE_NAME is required when LUANTI_SERVER_KIND=instance" >&2
		exit 1
	fi

	template_dir="${template_mount%/}/$template_name"
	if [ ! -d "$template_dir" ]; then
		echo "error: instance template directory not found: $template_dir" >&2
		exit 1
	fi

	echo "Bootstrapping instance template from $template_dir"
	cp -R "$template_dir"/. /home/container/
	touch "$template_marker"
}

escape_sed_replacement() {
	printf '%s' "${1:-}" | sed 's/[\/&]/\\&/g'
}

set_config_value() {
	file="$1"
	key="$2"
	value="$3"
	escaped=$(escape_sed_replacement "$value")

	if grep -Eq "^${key}[[:space:]]*=" "$file"; then
		sed -i "s#^${key}[[:space:]]*=.*#${key} = ${escaped}#" "$file"
		return 0
	fi

	printf '%s = %s\n' "$key" "$value" >> "$file"
}

apply_luanti_config() {
	config_file="/home/container/.luanti/luanti.conf"

	mkdir -p /home/container/.luanti
	[ -f "$config_file" ] || : > "$config_file"

	set_config_value "$config_file" "name" "${SERVER_ADMIN_NAME:-}"
	set_config_value "$config_file" "server_name" "${SERVER_NAME:-}"
	set_config_value "$config_file" "server_description" "${SERVER_DESC:-}"
	set_config_value "$config_file" "server_address" "${SERVER_DOMAIN:-}"
	set_config_value "$config_file" "server_url" "${SERVER_URL:-}"
	set_config_value "$config_file" "server_announce" "${SERVER_ANNOUNCE:-}"
	set_config_value "$config_file" "serverlist_url" "${SERVER_LIST_URL:-}"
	set_config_value "$config_file" "motd" "${SERVER_MOTD:-}"
	set_config_value "$config_file" "max_users" "${SERVER_MAX_USERS:-}"
	set_config_value "$config_file" "bind_address" "0.0.0.0"
	set_config_value "$config_file" "default_password" "${SERVER_PASSWORD:-}"
	set_config_value "$config_file" "default_game" "${DEFAULT_GAME:-}"
	set_config_value "$config_file" "enable_mod_channels" "${LUANTI_ENABLE_MOD_CHANNELS:-true}"
}

is_classrooms_pending_key() {
	case "$1" in
		enable_damage|enable_pvp|mcl_enable_hunger|mobs_spawn|only_peaceful_mobs|mcl_explosions_griefing|static_spawnpoint|classrooms_spawn_yaw|classrooms_spawn_pitch)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

apply_classrooms_pending_settings() {
	config_file="/home/container/.luanti/luanti.conf"
	pending_file="${CLASSROOMS_PENDING_SETTINGS_FILE:-${LUANTI_MOD_DATA_PATH}/classrooms_bridge/instance_settings.conf}"

	if [ ! -f "$pending_file" ]; then
		return 0
	fi

	echo "Applying classroom-managed pending settings from $pending_file"

	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			''|\#*)
				continue
				;;
			*=*)
				key="${line%%=*}"
				value="${line#*=}"
				key="$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
				value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
				;;
			*)
				echo "error: invalid classroom pending setting line: $line" >&2
				exit 1
				;;
		esac

		if ! is_classrooms_pending_key "$key"; then
			echo "error: unsupported classroom pending setting key: $key" >&2
			exit 1
		fi

		set_config_value "$config_file" "$key" "$value"
	done < "$pending_file"
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

# Enable server-side modchannels by default so proxy bridge mods can talk to
# mt-multiserver-proxy without extra container-side patching.
LUANTI_ENABLE_MOD_CHANNELS=${LUANTI_ENABLE_MOD_CHANNELS:-true}
export LUANTI_ENABLE_MOD_CHANNELS

# Force the user-data directory to .luanti so mods, games, worlds, and mod_data
# resolve under /home/container/.luanti even if a legacy .minetest directory exists.
LUANTI_USER_PATH=${LUANTI_USER_PATH:-/home/container/.luanti}
export LUANTI_USER_PATH

# Optional overrides for mounted games/mods/mod_data outside /home/container.
LUANTI_GAME_PATH=${LUANTI_GAME_PATH:-/home/container/.luanti/games}
export LUANTI_GAME_PATH

LUANTI_MOD_PATH=${LUANTI_MOD_PATH:-/home/container/.luanti/mods}
export LUANTI_MOD_PATH

LUANTI_MOD_DATA_PATH=${LUANTI_MOD_DATA_PATH:-$LUANTI_USER_PATH/mod_data}
export LUANTI_MOD_DATA_PATH

# Fix ownership on Luanti data paths at startup (helpful for SFTP uploads).
# Set LUANTI_FIX_PERMS=0 to disable.
LUANTI_FIX_PERMS=${LUANTI_FIX_PERMS:-1}
export LUANTI_FIX_PERMS

# If Pelican creates a server without an allocation it injects SERVER_PORT=0.
# Normalize that to a stable internal-only port so the server can still listen
# on the shared Docker network behind mt-multiserver-proxy.
SERVER_PORT=$(int_or_default "${SERVER_PORT:-}" "${LUANTI_INTERNAL_PORT:-30000}")
export SERVER_PORT

bootstrap_instance_template
apply_luanti_config
apply_classrooms_pending_settings

if env_enabled "$LUANTI_FIX_PERMS"; then
	mkdir -p /home/container/.luanti /home/container/.cache/luanti

	# Ensure uploaded files/directories are usable by the current runtime user.
	# This also fixes broken directory mode bits (missing +x) from some uploads.
	for path in \
		/home/container/.luanti \
		/home/container/.cache/luanti \
		/home/container/server.log
	do
		fix_path_permissions "$path"
	done

	if [ "$(id -u)" -eq 0 ]; then
		for path in \
			/home/container/.luanti \
			/home/container/.cache/luanti \
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
