#!/usr/bin/env bash
# lib.sh — shared utilities for Firefox hardening scripts
#
# Sourced by setup.sh, backup-bookmarks.sh, and cookie-exceptions.sh.
# Not intended to be executed directly.

FIREFOX_DIR="$HOME/Library/Application Support/Firefox"

# Prints the absolute path to the default-release Firefox profile directory.
# Parses profiles.ini with two passes to handle both Path-before-Name and
# Name-before-Path field orderings. Respects IsRelative flag.
# Returns 1 if the profile is not found.
find_profile() {
    local profiles_ini="$FIREFOX_DIR/profiles.ini"
    if [[ ! -f "$profiles_ini" ]]; then
        echo "Error: profiles.ini not found at $profiles_ini" >&2
        return 1
    fi

    local path="" is_relative=""
    local in_section=0
    while IFS='=' read -r key value; do
        key="${key#"${key%%[![:space:]]*}"}"   # trim leading whitespace
        key="${key%"${key##*[![:space:]]}"}"   # trim trailing whitespace
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        if [[ "$key" == "[Profile"* ]]; then
            in_section=1
            path=""
            is_relative=""
        elif [[ $in_section -eq 1 && "$key" == "Path" ]]; then
            path="$value"
        elif [[ $in_section -eq 1 && "$key" == "IsRelative" ]]; then
            is_relative="$value"
        elif [[ $in_section -eq 1 && "$key" == "Name" && "$value" == "default-release" ]]; then
            if [[ -n "$path" ]]; then
                if [[ "$is_relative" == "0" ]]; then
                    echo "$path"
                else
                    echo "$FIREFOX_DIR/$path"
                fi
                return 0
            fi
        fi
    done < "$profiles_ini"

    # Second pass: Name may appear before Path
    in_section=0
    local found_name=0
    while IFS='=' read -r key value; do
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        if [[ "$key" == "[Profile"* ]]; then
            in_section=1
            found_name=0
            path=""
            is_relative=""
        elif [[ $in_section -eq 1 && "$key" == "Name" && "$value" == "default-release" ]]; then
            found_name=1
        elif [[ $in_section -eq 1 && "$key" == "IsRelative" ]]; then
            is_relative="$value"
        elif [[ $in_section -eq 1 && "$key" == "Path" ]]; then
            path="$value"
            if [[ $found_name -eq 1 && -n "$path" ]]; then
                if [[ "$is_relative" == "0" ]]; then
                    echo "$path"
                else
                    echo "$FIREFOX_DIR/$path"
                fi
                return 0
            fi
        fi
    done < "$profiles_ini"

    echo "Error: default-release profile not found in profiles.ini" >&2
    return 1
}
