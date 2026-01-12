# See https://just.systems/man/en/ for information about how to use this file

# List all recipes
default:
    @just --list --justfile {{justfile()}}

# Download flatpak-builder-tools needed for the update-generated-sources.sh script
download-tools:
    #!/usr/bin/env bash
    if test -d tools; then
        git -C tools pull
    else
        git clone https://github.com/flatpak/flatpak-builder-tools.git tools
    fi


