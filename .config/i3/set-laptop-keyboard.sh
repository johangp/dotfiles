#!/bin/sh

device_id=$(xinput list --id-only 'AT Translated Set 2 keyboard' 2>/dev/null) || exit 0

if [ -n "$device_id" ]; then
    # Clear the shared XKB option state first, then load the swapped map only
    # onto the built-in keyboard. setxkbmap -device alone still shares the
    # option state through the X root window properties.
    setxkbmap -option ''
    setxkbmap -layout us -variant intl -option ctrl:swapcaps -print \
        | xkbcomp -I/usr/share/X11/xkb -i "$device_id" - "$DISPLAY" 2>/dev/null
fi
