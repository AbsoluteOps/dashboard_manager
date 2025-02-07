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
#   create_json_config "test.conf"
#   create_json_config "test.conf" "yes"
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
        echo "Warning: Config '$config_file' already exists and will not be overwritten."
        return 1
    elif [[ -e "$config_file" && "${override,,}" == "yes" ]]; then
        echo "Warning: Config '$config_file' exists but will be overwritten."
    else
        echo "Creating new config '$config_file'."
    fi

    echo "$json_template" > "$config_file" &&
      echo "Config file created: $config_file" ||
      echo "Error creating config file: $config_file"
}

########################################
# Validate the JSON configuration file.
#
# Usage:
#   is_valid_json_config "FILE.conf"
########################################
is_valid_json_config() {
    local config_file="$1"

#    echo "Validating JSON configuration file: '$config_file'"
    if [[ -e "$config_file" ]]; then
        if jq empty "$config_file" >/dev/null 2>&1; then
            echo "valid"
#            echo "  - '$config_file' is valid."
            return 0
        else
            echo "invalid"
#            echo "  - '$config_file' is not valid JSON."
            return 1
        fi
    else
#        echo "  - '$config_file' does not exist. Validation skipped."
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
        echo ""
        return 1
    fi
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
      echo "Set value at '${object_path}' to '${value}' in '$config_file'." ||
      { echo "Failed to set value at '${object_path}'."; rm -f "$tmp"; return 1; }
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
        echo "No object/key at '${object_path}' found in '$config_file'. Nothing to delete."
        return 1
    fi

    jq "del(.${object_path})" "$config_file" > "$tmp" &&
      mv "$tmp" "$config_file" &&
      echo "Deleted object/key at '${object_path}' in '$config_file'." ||
      { echo "Failed to delete '${object_path}'."; rm -f "$tmp"; return 1; }
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
        echo "Object/key at '${object_path}' exists in '$config_file'."
        return 0
    else
        echo "Object/key at '${object_path}' does not exist in '$config_file'."
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
        echo "No object found in '${object_path}' with '${key}' equal to '${value}'."
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
                echo "Duplicate found: Key '$key' with value '$new_value' already exists in '${object_path}'."
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
            echo "Failed to create '${object_path}' and add the new object in '$config_file'."
            rm -f "$tmp"
            return 1
        fi
    else
        if ! jq ".${object_path} += [${new_object}]" "$config_file" > "$tmp"; then
            echo "Failed to append the new object to '${object_path}' in '$config_file'."
            rm -f "$tmp"
            return 1
        fi
    fi

    mv "$tmp" "$config_file"
    echo "Added new object to '${object_path}' in '$config_file'."
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
        echo "Object with '${key}' equal to '${value}' not found in '${object_path}'. Nothing to delete."
        rm -f "$tmp"
        return 1
    fi

    jq --arg search "$search_value_lower" \
       ".${object_path} |= map(select((.${key} | ascii_downcase) != \$search))" \
       "$config_file" > "$tmp" && \
       mv "$tmp" "$config_file" && \
       echo "Deleted object from '${object_path}' where '${key}' is '${value}'." || \
       { echo "Failed to delete object from '${object_path}'."; rm -f "$tmp"; return 1; }

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
       { echo "Failed to update object value in '$config_file'."; rm -f "$tmp"; return 1; }
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
       { echo "Failed to add key/value to object in '$config_file'."; rm -f "$tmp"; return 1; }
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

# ------------------------------------------------------------------------------
# Testing only - You should delete this section and everything below as a module.
# Example usage:
# Uncomment and run the following lines to test the functions.
# ------------------------------------------------------------------------------

#: <<'EOF'
# config_file="test.conf"
#
## Create a new configuration file (override if needed)
#create_json_config "$config_file" "yes"
#
## Validate the configuration
#is_valid_json_config "$config_file"
#
## Write a new endpoint name value
#write_json_value "$config_file" "endpoint_data.endpoint_name" "New Endpoint"
#
## Read back the endpoint name
#read_json_value "$config_file" "endpoint_data.endpoint_name"
#
## Add a new monitor object (duplicate check will trigger if an existing monitor_id or monitor_name matches)
#add_json_object "$config_file" "monitor_data" '{"monitor_id": "001", "monitor_name": "Primary"}'
#
## Try to add a duplicate (this should warn and exit with error)
#add_json_object "$config_file" "monitor_data" '{"monitor_id": "001", "monitor_name": "Primary"}'
#
## Find the monitor object by monitor_name
#find_json_object "$config_file" "monitor_data" "monitor_name" "Primary"
#
## Update a key’s value in the monitor object
#update_object_value_search "$config_file" "monitor_data" "Primary" "monitor_name" "monitor_interval" "60s"
#
## Add a new key/value pair to the monitor object
#add_object_key_search "$config_file" "monitor_data" "Primary" "monitor_name" "alert_enabled" "true"
#
## Delete the monitor object by key/value
#delete_json_object "$config_file" "monitor_data" "monitor_name" "Primary"
#
## Count the number of monitor objects
#count_objects "$config_file" "monitor_data"
#
#EOF

# ------------------------------------------------------------------------------
# Built test cases by Steve
# ------------------------------------------------------------------------------

config_file1="test.conf"

echo "----------------TEST CASE 01"

create_json_config "$config_file1" "yes"
is_valid_json_config "$config_file1"

write_json_value "$config_file1" "endpoint_data.endpoint_name" "New Endpoint"
write_json_value "$config_file1" "endpoint_data.endpoint_id" "1001"

write_json_value "$config_file1" "endpoint_data.parent_endpoint_id" "2001"
write_json_value "$config_file1" "endpoint_data.parent_endpoint_name" "Parent Endpoint"

cat "$config_file1"

echo "----------------TEST CASE 02"

read_json_value "$config_file1" "endpoint_data.endpoint_name"
add_json_object "$config_file1" "monitor_data" '{"monitor_id": "001", "monitor_name": "Primary"}'
add_json_object "$config_file1" "monitor_data" '{"monitor_id": "002", "monitor_name": "Secondary"}'
add_json_object "$config_file1" "monitor_data" '{"monitor_id": "003", "monitor_name": "Ternary"}'

cat "$config_file1"

echo "----------------TEST CASE 03"

find_json_object "$config_file1" "monitor_data" "monitor_name" "Secondary"
update_object_value_search "$config_file1" "monitor_data" "Primary" "monitor_name" "monitor_interval" "60s"

cat "$config_file1"

echo "----------------TEST CASE 04"

add_json_object "$config_file1" "monitor_data" '{"monitor_id": "004", "monitor_name": "Test 4"}'
add_json_object "$config_file1" "monitor_data" '{"monitor_id": "005", "monitor_name": "Test 5"}'
add_object_key_search "$config_file1" "monitor_data" "Test 4" "monitor_name" "alert_enabled" "false"

cat "$config_file1"

echo "----------------TEST CASE 05"

delete_json_object "$config_file1" "monitor_data" "monitor_name" "Ternary"
count_objects "$config_file1" "monitor_data"

cat "$config_file1"

echo "----------------TEST CASE 06"

#add_json_object "$config_file1" "website_data" ''

cat "$config_file1"

echo "----------------TEST CASE 07"

add_json_object "$config_file1" "website_data" '{"website_id": "001", "website_name": "Website 1"}'
add_json_object "$config_file1" "website_data" '{"website_id": "002", "website_name": "Website 2"}'

cat "$config_file1"

echo "----------------TEST CASE 08"

delete_json_object "$config_file1" "website_data" "website_name" "website 1"
#delete_json_object "$config_file1" "website_data" "website_name" "website 2"

cat "$config_file1"

echo "----------------TEST CASE 09"

if ! find_json_object "$config_file1" "monitor_data" "monitor_name" "primary"; then
    echo "Didn't find monitor with 'primary'"
else
    echo "Found monitor with 'primary'"
fi

cat "$config_file1"

echo "----------------TEST CASE 10"

find_json_object "$config_file1" "monitor_data" "monitor_id" "005"
find_json_object "$config_file1" "website_data" "website_name" "website 2"

# Good example of finding an object and then pulling data or targetting an update after search.
search_object=$(find_json_object "$config_file1" "website_data" "website_name" "website 2")
found_website_id=$(echo "$search_object" | jq -r '.website_id')

echo "Found website id of: $found_website_id"
update_object_value_search "$config_file1" "website_data" "$found_website_id" "website_id" "website_interval" "30s"

cat "$config_file1"

echo ""
echo "----------------"
echo "Final result"
echo "----------------"

echo "Host details"
echo " - ID: $(read_json_value "$config_file1" "endpoint_data.endpoint_id") ($(read_json_value "$config_file1" "endpoint_data.endpoint_name"))"
parent_id=$(read_json_value "$config_file1" "endpoint_data.parent_endpoint_id")
parent_name=$(read_json_value "$config_file1" "endpoint_data.parent_endpoint_name")
if [[ -n "$parent_id" ]]; then
    echo " - Parent ID: $parent_id ($parent_name)"
fi

is_valid_file="$(is_valid_json_config "$config_file1")"
echo " - Configuration file ($config_file1) is $is_valid_file"

monitor_count=$(count_objects "$config_file1" "monitor_data")
website_count=$(count_objects "$config_file1" "website_data")


if (( monitor_count > 0 )); then
    echo " - Monitor Count: $monitor_count"
    for (( i=0; i < monitor_count; i++ )); do
        echo "   -- Display monitor $(( i + 1 )) of $monitor_count ..."
        current_id=$(read_json_value "$config_file1" "monitor_data[$i].monitor_id" || true)
        current_name=$(read_json_value "$config_file1" "monitor_data[$i].monitor_name" || true)
        echo "   --- Monitor ID: $current_id ($current_name)"
    done
else
    echo " - No Monitors"
fi


if (( website_count > 0 )); then
    echo " - Website Count: $website_count"
    for (( i=0; i < website_count; i++ )); do
        echo "   -- Display website $(( i + 1 )) of $website_count ..."
        current_id=$(read_json_value "$config_file1" "website_data[$i].website_id" || true)
        current_name=$(read_json_value "$config_file1" "website_data[$i].website_name" || true)
        echo "   --- Website ID: $current_id ($current_name)"
    done
else
    echo " - No Websites"
fi
echo ""















