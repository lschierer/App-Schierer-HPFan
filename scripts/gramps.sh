#!/bin/bash
# Set the 'home' for this project to the current directory
# Gramps will create a 'gramps' folder here for DBs and settings
export GRAMPSHOME="$(pwd)/share"

# Launch Gramps on macOS
/Applications/Gramps.app/Contents/MacOS/Gramps "$@"
