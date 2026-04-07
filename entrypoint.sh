#!/bin/sh

# Default the TZ environment variable to UTC.
TZ=${TZ:-UTC}
export TZ

# Switch to the container's working directory
cd /home/container || exit 1

# Convert all of the "{{VARIABLE}}" parts of the command into the expected shell
# variable format of "${VARIABLE}" before evaluating the string and automatically
# replacing the values.
PARSED=$(echo "$STARTUP" | sed -e 's/{{/${/g' -e 's/}}/}/g')

# Display the command we're running in the output, and then execute it
# exec replaces the shell process so luantiserver gets direct stdin/stdout
# stdbuf disables output buffering so ncurses redraws are captured immediately
echo "container~ $PARSED"
exec $PARSED
