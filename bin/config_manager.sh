#!/bin/bash

# Description: Use to read/write from/to JSON configuration files.
# Expectation: This module requires the logger module is loaded first.
#
# Add this module to the <script>/bin directory.
# Import into parent script: source $SCRIPT_DIR/bin/config_manager.sh
#
# This module uses several different functions to manipulate data as needed. In general,
# most functions require at minimum the config file and up from each of these vars.
# Structure: <action> <config_file> <object_path> <array_object> <search_key> <search_key_value> <key> <value>
#   <action>           - One of several actions that can be taken depending on the intent.
#   <config_file>      - Configuration file(s) that must be created, read and/or written from and to.
#   <object_path>      - The JSON path of the object. Usage varies depending on the action.
#   <array_object>     - High level array object like "monitor_data" or "website_data".
#   <search_key>       - Key used to search for a search key value. Often used for search and update/delete functions.
#   <search_key_value> - Value to search for based on search_key.
#   <key>              - Key to update.
#   <value>            - Value used to update key.
#
# Usage Examples:
#   create_json_config "FILE.conf"
#   is_valid_json_config "FILE.conf"
#
#   read_json_value "FILE.conf" "endpoint_data.endpoint_name"
#   write_json_value "FILE.conf" "endpoint_data.endpoint_name" "New Endpoint Name"
#   delete_json_key "FILE.conf" "endpoint_data"
#
#   verify_json_exists "FILE.conf" "monitor_data[3].monitor_name"
#   find_json_object "FILE.conf" "monitor_data" "monitor_name" "Test Monitor 1E"
#
#   add_json_object "FILE.conf" "monitor_data" '{"monitor_id": "123", "monitor_name": "Primary"}'
#   delete_json_object "FILE.conf" "monitor_data" "monitor_name" "Primary"
#
#   update_object_value_search "FILE.conf" "monitor_data" "Primary" "monitor_name" "monitor_interval" "60s"
#   add_object_key_search "FILE.conf" "monitor_data" "Primary" "monitor_name" "new_key" "new_value"
#
#   count_objects "FILE.conf" "monitor_data"
#

########################################
# Create new configuration file.
#
# Usage:
#   create_json_config <conf_file> [<override:NO|yes>]
# Examples:
#   create_json_config "FILE.conf"
#   create_json_config "FILE.conf" "yes"
########################################
create_json_config() {
    local config_file="$1"
    local override="${2:-no}"

    local json_template='{
  "endpoint_data": {
    "endpoint_id": "",
    "endpoint_name": "",
    "parent_endpoint_name": "",
    "parent_endpoint_id": ""
  },
  "monitor_data": []
}'

    if [[ -e "$config_file" && "${override,,}" != "yes" ]]; then
        log "Warning: Config '$config_file' already exists and will not be overwritten." warn
        return 1
    elif [[ -e "$config_file" && "${override,,}" == "yes" ]]; then
        log "Warning: Config '$config_file' exists but will be overwritten." warn
    else
        log "Creating new config: '$config_file'."
    fi

    echo "$json_template" > "$config_file" &&
      log "Config file created: $config_file" ||
      log "Error creating config file: $config_file" error
}

########################################
# Validate the JSON configuration file.
#
# Usage:
#   is_valid_json_config "FILE.conf"
########################################
is_valid_json_config() {
    local config_file="$1"

    log "Validating JSON configuration file: '$config_file'"
    if [[ -e "$config_file" ]]; then
        if jq empty "$config_file" >/dev/null 2>&1; then
            echo "valid"
            log "  - '$config_file' is valid."
            return 0
        else
            echo "invalid"
            log "  - '$config_file' is not valid JSON." error
            return 1
        fi
    else
        log "  - '$config_file' does not exist. Validation skipped." error
        return 1
    fi
}

########################################
# Read a value from a nested object/key.
#
# Usage:
#   read_json_value "FILE.conf" "endpoint_data.endpoint_name"
#   read_json_value "FILE.conf" "monitor_data[2].monitor_name"
########################################
read_json_value() {
    local config_file="$1"
    local object_path="$2"
    local value
    value=$(jq -r ".${object_path}" "$config_file")

    if [[ "$value" == "null" || -z "$value" ]]; then
        # Value is unset or null
        log "Read value from $object_path is empty"
        echo ""
        return 1
    fi
    log "Read value from $object_path is: $value"
    echo "$value"
    return 0
}

########################################
# Write (or update) a value in a nested object/key.
#
# Usage:
#   write_json_value "FILE.conf" "endpoint_data.endpoint_name" "New Endpoint Name"
#
# Note: The value is passed as a plain string.
########################################
write_json_value() {
    local config_file="$1"
    local object_path="$2"
    local value="$3"
    local tmp
    tmp=$(mktemp)

    # Using --arg to properly escape the new value as a string.
    jq --arg value "$value" ".${object_path} = \$value" "$config_file" > "$tmp" &&
      mv "$tmp" "$config_file" &&
      log "Set value at '${object_path}' to '${value}' in '$config_file'." ||
      { log "Failed to set value at '${object_path}'." error; rm -f "$tmp"; return 1; }
}

########################################
# Delete a key or object from the configuration.
#
# Usage:
#   delete_json_key "FILE.conf" "endpoint_data.endpoint_name"
#   delete_json_key "FILE.conf" "endpoint_data"
########################################
delete_json_key() {
    local config_file="$1"
    local object_path="$2"
    local tmp
    tmp=$(mktemp)

    if ! jq -e ".${object_path}" "$config_file" >/dev/null 2>&1; then
        log "No object/key at '${object_path}' found in '$config_file'. Nothing to delete." warn
        return 1
    fi

    jq "del(.${object_path})" "$config_file" > "$tmp" &&
      mv "$tmp" "$config_file" &&
      log "Deleted object/key at '${object_path}' in '$config_file'." ||
      { log "Failed to delete '${object_path}'." error; rm -f "$tmp"; return 1; }
}

########################################
# Verify that a key or object exists in the configuration.
#
# Usage:
#   verify_json_exists "FILE.conf" "endpoint_data"
#   verify_json_exists "FILE.conf" "monitor_data[3].monitor_name"
########################################
verify_json_exists() {
    local config_file="$1"
    local object_path="$2"

    if jq -e ".${object_path}" "$config_file" >/dev/null 2>&1; then
        log "Object/key at '${object_path}' exists in '$config_file'."
        return 0
    else
        log "Object/key at '${object_path}' does not exist in '$config_file'." error
        return 1
    fi
}

########################################
# Search for an object in an array based on a key-value pair.
#
# Usage:
#   find_json_object "FILE.conf" "monitor_data" "monitor_name" "Test Monitor 1E"
########################################
find_json_object() {
    local config_file="$1"
    local object_path="$2"   # e.g., monitor_data
    local key="$3"
    local value="$4"
    local result

    # For case-insensitive match when value is purely alphabetic.
    local search_val
#    search_val=$(echo "$value" | tr '[:upper;]' '[:lower:]')
    search_val=$(echo "${value,,}")

    result=$(jq -r ".${object_path}[] | select((.${key} | ascii_downcase) == \"${search_val}\")" "$config_file")

#    if [[ "$value" =~ ^[a-zA-Z]+$ ]]; then
#        result=$(jq -r ".${object_path}[] | select(.${key} | ascii_downcase == \"$(echo "$value" | tr '[:upper:]' '[:lower:]')\")" "$config_file")
#    else
#        result=$(jq -r ".${object_path}[] | select(.${key} == \"${value}\")" "$config_file")
#    fi

    if [[ -z "$result" ]]; then
        log "No object found in '${object_path}' with '${key}' equal to '${value}'." warn
        return 1
    fi

    echo "$result"
    return 0
}

########################################
# Add a new object to an array (with duplicate checking on *_id and *_name keys).
#
# Usage:
#   add_json_object "FILE.conf" "monitor_data" '{"monitor_id": "123", "monitor_name": "Primary"}'
#
# If the array does not exist, it will be created.
########################################
add_json_object() {
    local config_file="$1"
    local object_path="$2"   # e.g., monitor_data
    local new_object="$3"    # Must be a valid JSON object string.
    local duplicate_found=0
    local key new_value
    local new_keys

    # Extract keys from the new object.
    new_keys=$(echo "$new_object" | jq -r 'keys[]')

    # Check for duplicate keys (for any key ending with _id or _name).
    for key in $new_keys; do
        if [[ "$key" =~ _id$ || "$key" =~ _name$ ]]; then
            new_value=$(echo "$new_object" | jq -r ".${key}")
            if jq -e ".${object_path}[] | select(.${key} == \"${new_value}\")" "$config_file" >/dev/null 2>&1; then
                log "Duplicate found: Key '$key' with value '$new_value' already exists in '${object_path}'." error
                duplicate_found=1
                break
            fi
        fi
    done

    if [[ "$duplicate_found" -eq 1 ]]; then
        return 1
    fi

    local tmp
    tmp=$(mktemp)
    # If the array does not exist, create it with the new object.
    if ! jq -e ".${object_path}" "$config_file" >/dev/null 2>&1; then
        if ! jq ".${object_path} = [${new_object}]" "$config_file" > "$tmp"; then
            log "Failed to create '${object_path}' and add the new object in '$config_file'." error
            rm -f "$tmp"
            return 1
        fi
    else
        if ! jq ".${object_path} += [${new_object}]" "$config_file" > "$tmp"; then
            log "Failed to append the new object to '${object_path}' in '$config_file'." error
            rm -f "$tmp"
            return 1
        fi
    fi

    mv "$tmp" "$config_file"
    log "Added new object to '${object_path}' in '$config_file'."
    return 0
}

########################################
# Delete an object from an array based on a key-value match.
#
# Usage:
#   delete_json_object "FILE.conf" "monitor_data" "monitor_name" "Primary"
########################################
delete_json_object() {
    local config_file="$1"
    local object_path="$2"
    local key="$3"
    local value="$4"
    local tmp
    tmp=$(mktemp)

    # Convert the provided search value to lowercase.
    local search_value_lower
    search_value_lower=$(echo "$value" | tr '[:upper:]' '[:lower:]')

    # Use --arg to pass the lowercase search value into jq.
    if ! jq --arg search "$search_value_lower" -e \
        ".${object_path}[] | select((.${key} | ascii_downcase) == \$search)" \
        "$config_file" >/dev/null 2>&1; then
        log "Object with '${key}' equal to '${value}' not found in '${object_path}'. Nothing to delete." error
        rm -f "$tmp"
        return 1
    fi

    jq --arg search "$search_value_lower" \
       ".${object_path} |= map(select((.${key} | ascii_downcase) != \$search))" \
       "$config_file" > "$tmp" && \
       mv "$tmp" "$config_file" && \
       log "Deleted object from '${object_path}' where '${key}' is '${value}'." || \
       { log "Failed to delete object from '${object_path}'." error; rm -f "$tmp"; return 1; }

# WORKING, but case sensitive
#    if ! jq -e ".${object_path}[] | select(.${key} == \"${value}\")" "$config_file" >/dev/null 2>&1; then
#        echo "Object with '${key}' equal to '${value}' not found in '${object_path}'. Nothing to delete."
#        rm -f "$tmp"
#        return 1
#    fi
#
#    jq ".${object_path} |= map(select(.${key} != \"${value}\"))" "$config_file" > "$tmp" &&
#      mv "$tmp" "$config_file" &&
#      echo "Deleted object from '${object_path}' where '${key}' is '${value}'." ||
#      { echo "Failed to delete object from '${object_path}'."; rm -f "$tmp"; return 1; }
}

########################################
# Update a key's value in an object found in an array
# by searching for a given key/value pair.
#
# Requirement 11.
#
# Usage:
#   update_object_value_search "FILE.conf" "monitor_data" "Primary" "monitor_name" "monitor_interval" "60s"
########################################
update_object_value_search() {
    local config_file="$1"
    local array_key="$2"           # e.g., monitor_data
    local search_value="$3"        # The value to search for (e.g., Primary)
    local key_to_search="$4"       # The key to check (e.g., monitor_name)
    local key_to_update="$5"       # The key to update (e.g., monitor_interval)
    local new_value="$6"           # New value (as a string)
    local tmp
    tmp=$(mktemp)

    jq --arg search "$search_value" \
       --arg keysearch "$key_to_search" \
       --arg keyupdate "$key_to_update" \
       --arg value "$new_value" \
       ".${array_key} |= map(
           if .[\$keysearch] == \$search then
               .[\$keyupdate] = \$value
           else .
           end
       )" "$config_file" > "$tmp" &&
       mv "$tmp" "$config_file" ||
       { log "Failed to update object value in '$config_file'." error; rm -f "$tmp"; return 1; }
}

########################################
# Add a new key-value pair to an object in an array after finding it by a search key/value.
#
# Usage:
#   add_object_key_search "FILE.conf" "monitor_data" "Primary" "monitor_name" "new_key" "new_value"
########################################
add_object_key_search() {
    local config_file="$1"
    local array_key="$2"
    local search_value="$3"
    local key_to_search="$4"
    local new_key="$5"
    local new_value="$6"
    local tmp
    tmp=$(mktemp)

    jq --arg search "$search_value" \
       --arg keysearch "$key_to_search" \
       --arg newkey "$new_key" \
       --arg newval "$new_value" \
       ".${array_key} |= map(
           if .[\$keysearch] == \$search then
               .[\$newkey] = \$newval
           else .
           end
       )" "$config_file" > "$tmp" &&
       mv "$tmp" "$config_file" ||
       { log "Failed to add key/value to object in '$config_file'." error; rm -f "$tmp"; return 1; }
}

########################################
# Count the number of items in a given array field.
#
# Usage:
#   count_objects "FILE.conf" "monitor_data"
########################################
count_objects() {
    local config_file="$1"
    local array_key="$2"

    jq ".${array_key} | length" "$config_file"
}

