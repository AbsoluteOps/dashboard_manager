#!/bin/bash

# If you change this you must also change the path
# in the uninstall() function.
ROOTDIR=/opt/dashboard
BINDIR="$ROOTDIR/bin"
ETCDIR="$ROOTDIR/etc"

# Logging vars (review log() info for more context)
LOGDIR="$ROOTDIR/log"
LOGFILE="$LOGDIR/dashboard_manager.log"
LOGFILE_MONITOR="$LOGDIR/dashboard_monitor.log"
LOGFILE_CONTROLLER="$LOGDIR/dashboard_controller.log"

CONFIG="$ETCDIR/config.settings"
CUSTOMBINDIR="$ROOTDIR/custom"
MONITORREGISTER="$ETCDIR/monitor.register"

API_KEY=""
ENDPOINT_ID=""

declare -a INSTALLED_MONITORS
declare -a AVAILABLE_MONITORS

function usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -a, --api-key KEY               (Required) Set the API key."
    echo "  -n, --endpoint-name NAME        Set the endpoint name."
    echo "  -m, --install-monitors          Install all default monitors."
    echo "  -c, --custom-monitor PATH       Install a custom monitor."
    echo "  -k, --custom-monitor-name NAME  Set the name for the custom monitor."
    echo "  -u, --uninstall                 Uninstall the dashboard."
    echo "  -h, --help                      Show this help message."
    exit 1
}

API_KEY_FLAG=""
ENDPOINT_NAME=""
INSTALL_MONITORS=false
UNINSTALL=false
INTERACTIVE=true

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -a|--api-key)
            API_KEY_FLAG="$2"
            INTERACTIVE=false
            shift
            ;;
        -n|--endpoint-name)
            ENDPOINT_NAME="$2"
            shift
            ;;
        -C|--custom-monitor)
            CUSTOM_MONITOR_PATH="$2"
            shift
            ;;
        -N|--custom-monitor-name)
            CUSTOM_MONITOR_NAME="$2"
            shift
            ;;
        -A|--custom-monitor-args)
            CUSTOM_MONITOR_ARGS="$2"
            shift
            ;;
        -m|--install-monitors)
            INSTALL_MONITORS=true
            ;;
        -u|--uninstall)
            UNINSTALL=true
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown parameter passed: $1"
            usage
            ;;
    esac
    shift
done

if [[ -z "$API_KEY_FLAG" ]]; then
    echo "Error: --api-key is required."
    usage
fi

if [[ -n "CUSTOM_MONITOR_PATH" && -z "$CUSTOM_MONITOR_NAME" ]]; then
    echo "Error: --custom-monitor-name is required with --custom-monitor."
    usage
fi

if [[ -n "CUSTOM_MONITOR_NAME" && -n "INSTALL_MONITORS" ]]; then
    echo "Error: --custom-monitor-name cannot be used with --install-monitors."
    usage
fi

log() {
    # Description: Use to log other functions results.
    # Expectation: LOGDIR and LOGFILE variables are defined.
    # Structure: log "<message>" <optional:log_level> <optional:quiet_bool> <optional:log_type>
    #   "<message>"   Message enclosed in double quotes to act as initial value.
    #   <log_level>   Whatever log level. Current expecting: info (default), warn, error, other.
    #   <quiet_bool>  Bool for quiet (true/false). Used to remove output to user when true, but still sends to log.
    #   <log_type>    General is defaulted/assumed. When define, must add other optionals. Allowed types:
    #                 - GENERAL     Sends to LOGFILE
    #                 - MONITOR     Sends to LOGFILE_MONITOR
    #                 - CONTROLLER  Sends to LOGFILE_CONTROLLER
    #                 - ALL         Sends to all configured log files in log()
    #                 - <Other>     More can be added as long as LOGFILE_<TYPE> is set
    # Usage Examples:
    #   log "My info message to user and log file"
    #   log "My info message to user and log file" info
    #   log "My info message to log file only" info true
    #   log "My info message to controller log file only" info true controller
    #   log "My error message to user and log file" error
    #   log "My error message to log file only" error true
    #   log "My warn message to monitor log file and user" warn false monitor
    #   log "Some info message for all logs" info false all

    # Provided internal vars
    local log_msg="$1"
    local log_level="${2:-info}"
    local quiet="${3:-false}"
    local log_type="${4:-general}"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Capitalize log level and format it to fit within 8-character brackets
    local log_level_formatted
    log_level_formatted=$(printf "[%-5s]" "${log_level^^}")

    # Define the log entry format
    local log_entry="[$timestamp] $log_level_formatted $log_msg"

    # Log to file
    case "${log_type,,}" in
        "general")
            echo "$log_entry" >> "$LOGFILE"
            ;;
        "monitor")
            echo "$log_entry" >> "$LOGFILE_MONITOR"
            ;;
        "controller")
            echo "$log_entry" >> "$LOGFILE_CONTROLLER"
            ;;
        "all")
            echo "$log_entry" >> "$LOGFILE"
            echo "$log_entry" >> "$LOGFILE_MONITOR"
            echo "$log_entry" >> "$LOGFILE_CONTROLLER"
            ;;
        *)
            echo "INVALID LOG_TYPE for Log function used" >> "$LOGFILE"
            exit 1
            ;;
    esac

    # Display to user unless "quiet" is set to true
    if [[ "$quiet" != true ]]; then
        echo "  $log_msg"
    fi
}

is_valid_endpoint_name() {
    local input_string=$1

    if [[ -z "$input_string" ]]; then
        log "Invalid endpoint name (empty): ${input_string}" error
        return 1  # Invalid: empty string
    elif [[ ${#input_string} -lt 3 ]]; then
        log "Invalid endpoint name (too short): ${input_string}" error
        return 1  # Invalid: less than 3 characters
    elif [[ $input_string =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log "Endpoint name (valid): ${input_string}" info
        return 0  # Valid string
    else
        log "Invalid endpoint name (error): ${input_string}" error
        return 1  # Invalid string
    fi
}

check_root() {
    # Make sure logging is ready
    mkdir -p "$LOGDIR"
    touch "$LOGFILE"

    if [ "$EUID" -ne 0 ]; then
        log "This script must be run as root. Exiting..." error
        exit 1
    fi
}

check_dashboard_user() {
    if ! id -u dashboard >/dev/null 2>&1; then
        if [[ "$INTERACTIVE" == true ]]; then
            read -p "The 'dashboard' user does not exist. Do you want to create it? (y/n): " create_user
        else
            create_user="y"
        fi

        if [ "$create_user" == "y" ]; then
            sudo useradd -r -s /usr/sbin/nologin -d $ROOTDIR dashboard
            log "'dashboard' user created."
        else
            log "User creation declined. Exiting..." error
            exit 1
        fi
    fi
}

check_jq_installed() {
    if ! command -v jq &> /dev/null; then
        log "jq is not installed. Please install jq to proceed." error
        exit 1
    fi
}

init() {
    mkdir -p "$BINDIR"
    mkdir -p "$CUSTOMBINDIR"
    mkdir -p "$ETCDIR"

    touch "$CONFIG"
    touch "$MONITORREGISTER"
    touch "$LOGFILE_MONITOR"
    touch "$LOGFILE_CONTROLLER"

    chown dashboard "$LOGFILE" "$LOGFILE_MONITOR" "$LOGFILE_CONTROLLER"

    exec > >(tee -a "$LOGFILE_CONTROLLER") 2>&1
    exec 2>&1

    log "---------------------------" info true all
    log "Starting dashboard..." info true all
}

check_cron_service() {
    if systemctl list-unit-files | grep -q '^cron\.service'; then
        service_name="cron"
    elif systemctl list-unit-files | grep -q '^crond\.service'; then
        service_name="crond"
    else
        log "No cron service found. Exiting..." error
        exit 1
    fi

    if ! systemctl is-enabled $service_name >/dev/null 2>&1; then
        if [[ "$INTERACTIVE" == true ]]; then
            read -p "$service_name is not enabled. Do you want to enable it? (y/n): " enable_cron
        else
            enable_cron="y"
        fi

        if [ "$enable_cron" == "y" ]; then
            sudo systemctl enable $service_name
            sudo systemctl start $service_name
            if ! systemctl is-active $service_name >/dev/null 2>&1; then
                log "Failed to start $service_name. Exiting..." error
                exit 1
            fi
            log "$service_name enabled and started."
        else
            log "$service_name not enabled. Exiting..." error
            exit 1
        fi
    fi
}

prompt_api_key() {
    if [ -f $ETCDIR/api_key ]; then
        log "Found an API key at $ETCDIR/api_key."
        API_KEY=$(cat $ETCDIR/api_key)
    else
        read -p "Please enter your API key: " API_KEY
        read -p "Do you want to save the API key? (y/n): " save_key
        if [ "$save_key" == "y" ]; then
            echo $API_KEY > $ETCDIR/api_key
            log "API key saved to $ETCDIR/api_key."
        fi
    fi
}

check_endpoint_info() {
    if [ -f $ETCDIR/system_info ]; then
        current_system_info=$(cat $ETCDIR/system_info)
    else
        current_system_info=""
    fi

    private_ip=$(hostname -I | awk '{print $1}')
    os_vendor=$(lsb_release -i | awk -F: '{print $2}' | xargs)
    os_version=$(lsb_release -r | awk -F: '{print $2}' | xargs)
    cpu_number=$(nproc)
    ram_amount=$(free -m | awk '/^Mem:/{print $2}')

    new_system_info=$(cat <<EOF
private_ip=$private_ip
os_vendor=$os_vendor
os_version=$os_version
cpu_number=$cpu_number
ram_amount=$ram_amount
EOF
)

    if [ "$current_system_info" != "$new_system_info" ]; then
        response=$(curl --silent --request POST \
            --url "https://dashboard.absoluteops.com/api/endpoints/$ENDPOINT_ID" \
            --header "Authorization: Bearer $API_KEY" \
            --header 'Content-Type: multipart/form-data' \
            --form "private_ip=$private_ip" \
            --form "os_vendor=$os_vendor" \
            --form "os_version=$os_version" \
            --form "cpu_number=$cpu_number" \
            --form "ram_amount=$ram_amount")

        if echo $response | grep -q '"id"'; then
            log "Endpoint information updated successfully."
            echo "$new_system_info" > $ETCDIR/system_info
        else
            log "Failed to update endpoint information. Exiting..." error
            exit 1
        fi
    else
        log "System information has not changed. No update needed."
    fi
}

get_script_name_from_monitor_name() {
    monitor_name=$1
    script_name=""

    for monitor in monitors/default/*; do
        default_name=$(grep -oP '# Name: \K.*' "$monitor")
        if [ "$default_name" == "$monitor_name" ]; then
            script_name=$monitor
            break
        fi
    done

    echo "$script_name"
}

rename_endpoint() {
    read -p "Enter the new name (3+ characters, a-zA-Z0-9_-): " new_name
    if ! is_valid_endpoint_name "$new_name"; then
        log "You entered $new_name which is not valid." error
        return 1
    fi
    read -p "You entered $new_name. Are you sure this is what you want to use? (y/n): " confirm_name
    if [ "$confirm_name" == "y" ]; then
        check_endpoint_exists $new_name
    else
        log "Please try again." warn
        return 1
    fi
    return 0
}

check_endpoint_exists() {
    if [ -f $ETCDIR/endpoint_id ]; then
        ENDPOINT_ID=$(cat $ETCDIR/endpoint_id)
        if [[ $ENDPOINT_ID =~ ^[0-9]+$ ]]; then
            log "Endpoint ID $ENDPOINT_ID already exists at $ETCDIR/endpoint_id."
            check_endpoint_info
            return
        else
            log "Invalid endpoint ID found in $ETCDIR/endpoint_id. Proceeding with API check..." error
        fi
    fi

    if [ "$1" != "" ]; then
        hostname=$1
    else
        hostname=$(hostname)
    fi

    read -p "This endpoint will be named $hostname. Do you want to keep that name? (y/n): " keep_name
    if [ "$keep_name" != "y" ]; then
        until rename_endpoint; do
            log "Rename failed, retrying..." warn
        done
    fi

    response=$(curl --silent --request GET \
        --url 'https://dashboard.absoluteops.com/api/endpoints/' \
        --header "Authorization: Bearer $API_KEY")

    if echo $response | grep -q "\"name\":\"$hostname\""; then
        log "Endpoint with hostname $hostname already exists." warn
        read -p "Do you want to reuse it, or give this server a custom name? (reuse/rename): " exists_action
        if [ "$exists_action" == "reuse" ]; then
            ENDPOINT_ID=$(echo $response | jq -r ".data[] | select(.name == \"$hostname\") | .id")
            echo $ENDPOINT_ID > $ETCDIR/endpoint_id
            echo $hostname > $ETCDIR/endpoint_name
            check_endpoint_info
            return 0
        elif [ "$exists_action" == "rename" ]; then
            until rename_endpoint; do
                log "Rename failed, retrying..." warn
            done
        else
            log "Invalid input: $exists_action" error
            exit 1
        fi
    fi

    read -p "No endpoint with hostname $hostname found. Do you want to create it? (y/n): " create_endpoint
    if [ "$create_endpoint" == "y" ]; then
        log "Creating endpoint..."
        create_response=$(curl --silent --request POST \
            --url 'https://dashboard.absoluteops.com/api/endpoints' \
            --header "Authorization: Bearer $API_KEY" \
            --header 'Content-Type: multipart/form-data' \
            --form "name=$hostname")

        ENDPOINT_ID=$(echo $create_response | jq -r ".data.id")
        echo $ENDPOINT_ID > $ETCDIR/endpoint_id
        echo $hostname > $ETCDIR/endpoint_name
        check_endpoint_info
        log "Endpoint created with ID $ENDPOINT_ID."
    else
        log "Endpoint creation failed. Exiting..." error
        exit 1
    fi
}

get_installed_monitors() {
    INSTALLED_MONITORS=()

    if [ -f $MONITORREGISTER ]; then
        while IFS=';' read -r monitor_name monitor_path monitor_id; do
            INSTALLED_MONITORS+=("$monitor_name")
        done < $MONITORREGISTER
    else
        log "Error: $MONITORREGISTER file not found." error
        return 1
    fi
}

install_crontab_entry() {
    monitor_script=$1
    monitor_id=$2
    monitor_code=$3
    monitor_user=$4
    period_unit=$5
    period_value=$6
    monitor_args=$7

    # Convert period to cron format
    case $period_unit in
        "minutes")
            cron_schedule="*/$period_value * * * *"
            ;;
        "hours")
            cron_schedule="0 */$period_value * * *"
            ;;
        "days")
            cron_schedule="0 0 */$period_value * *"
            ;;
        "weeks")
            cron_schedule="0 0 * * */$period_value"
            ;;
        *)
            log "Unsupported period unit: $period_unit. Skipping..." error
            ;;
    esac

    # Add crontab entry with monitor code
    if ! grep -q "dashboard $monitor_script .* $monitor_args\? # Dashboard" /etc/crontab; then
        echo "$cron_schedule $monitor_user $monitor_script $monitor_code $monitor_args # Dashboard $monitor_id" >> /etc/crontab
    else
        log "Crontab entry for $monitor_script already exists." warn
    fi
}

check_and_create_monitor() {
    monitor=$1
    monitor_name=$2
    monitor_user=$3
    monitor_period=$4
    monitor_threshold=$5
    monitor_direction=$6
    monitor_args=$7

    period_value=$(echo $monitor_period | awk '{print $1}')
    period_unit=$(echo $monitor_period | awk '{print $2}')

    # Set the grace period based on the period unit
    case $period_unit in
        "minutes")
            grace_period=$((period_value * 2))
            grace_unit="minutes"
            ;;
        "hours")
            grace_period=1
            grace_unit="hours"
            ;;
        "days")
            grace_period=6
            grace_unit="hours"
            ;;
        "weeks")
            grace_period=1
            grace_unit="days"
            ;;
        *)
            log "Unsupported period unit: $period_unit. Skipping..." error
            return 1
            ;;
    esac

    # Check if the monitor already exists using the API
    response=$(curl --silent --request GET \
        --url "https://dashboard.absoluteops.com/api/monitors/?endpoint_id=$ENDPOINT_ID" \
	--header "Authorization: Bearer $API_KEY")

    if echo $response | grep -q "\"name\":\"$monitor_name\""; then
        monitor_id=$(echo "$response" | jq -r --arg name "$monitor_name" '.data[] | select(.name == $name) | .id')
        monitor_code=$(echo "$response" | jq -r --arg name "$monitor_name" '.data[] | select(.name == $name) | .code')
	    log "found monitor $monitor_id"
    else
        # Create the monitor using the API
        create_response=$(curl --silent --request POST \
            --url 'https://dashboard.absoluteops.com/api/monitors' \
            --header "Authorization: Bearer $API_KEY" \
            --header 'Content-Type: multipart/form-data' \
            --form "name=$monitor_name" \
            --form "endpoint_id=$ENDPOINT_ID" \
            --form "run_interval=$period_value" \
            --form "run_interval_type=$period_unit" \
            --form "run_interval_grace=$grace_period" \
            --form "run_interval_grace_type=$grace_unit" \
            --form "monitor_breach_value=$monitor_threshold" \
            --form "monitor_breach_value_type=$monitor_direction")

        monitor_id=$(echo $create_response | jq -r '.data.id')

        if [ -n "$monitor_id" ] && [ "$monitor_id" != "null" ]; then
            # Query the monitor to get the code
            monitor_response=$(curl --silent --request GET \
                --url "https://dashboard.absoluteops.com/api/monitors/$monitor_id" \
                --header "Authorization: Bearer $API_KEY")

            monitor_code=$(echo $monitor_response | jq -r '.data.code')
        else
            log "Failed to create monitor $monitor_name. Skipping..." error
            return 1
        fi
    fi

    if [ -n "$monitor_code" ] && [ "$monitor_code" != "null" ]; then
        install_crontab_entry $monitor $monitor_id $monitor_code $monitor_user $period_unit $period_value "$monitor_args"
        echo "$monitor_name;$monitor;$monitor_id" >> $MONITORREGISTER
        return 0
    else
        log "Failed to retrieve monitor code for $monitor_name. Skipping..." error
        return 1
    fi
}

install_default_monitor() {
    monitor=$1
    monitor_name=$(grep -oP '# Name: \K.*' $monitor)
    log "Installing $monitor_name..."
    monitor_script=$(basename $monitor)

    cp $monitor $BINDIR/
    monitor_dest=$BINDIR/$monitor_script
    chmod +x $monitor_dest

    monitor_user=$(grep -oP '# User: \K.*' $monitor)
    monitor_period=$(grep -oP '# Period: \K.*' $monitor)
    monitor_threshold=$(grep -oP '# Threshold: \K.*' $monitor)
    monitor_direction=$(grep -oP '# Direction: \K.*' $monitor)
    monitor_args=$(grep -oP '# Args: \K.*' "$monitor")

    # Check and create monitor if it doesn't exist
    check_and_create_monitor "$monitor_dest" "$monitor_name" $monitor_user "$monitor_period" $monitor_threshold $monitor_direction "$monitor_args"
    if [ $? -eq 0 ]; then
        log "Installed $monitor..."
    fi
}

install_default_monitors() {
    log "Installing default monitors..."
    for monitor in monitors/default/*; do
        install_default_monitor $monitor
    done
}

install_custom_monitor() {
    if [[ "$INTERACTIVE" == true ]]; then
        read -p "Enter the path to the custom monitor script: " script_path
    else
        script_path=$CUSTOM_MONITOR_PATH
    fi

    # Confirm the script exists
    if [ ! -f "$script_path" ]; then
        log "Error: Script not found at $script_path" error
        return 1
    fi

    default_name=$(grep -oP '# Name: \K.*' "$script_path")
    default_user=$(grep -oP '# User: \K.*' "$script_path")
    default_period=$(grep -oP '# Period: \K.*' "$script_path")
    default_threshold=$(grep -oP '# Threshold: \K.*' "$script_path")
    default_direction=$(grep -oP '# Direction: \K.*' "$script_path")
    default_args=$(grep -oP '# Args: \K.*' "$script_path")
    default_period_value=$(echo $default_period | grep -oP '\d+')
    default_period_unit=$(echo $default_period | grep -oP '\d+\K.*' | xargs)

    # Prompt for monitor name, suggesting the default if available
    if [[ "$INTERACTIVE" == true ]]; then
        read -p "Enter the monitor name [${default_name}]: " monitor_name
        read -p "Enter the user to run the monitor [${default_user}]: " monitor_user
        read -p "Enter the period value (e.g., 5) [${default_period_value}]: " period_value
        read -p "Enter the period unit (minutes/hours/days/weeks) [${default_period_unit}]: " period_unit
        read -p "Enter the threshold (e.g., 80%) [${default_threshold}]: " monitor_threshold
        read -p "Enter the direction (Above/Below) [${default_direction}]: " monitor_direction
        read -p "Enter any additional arguments for the monitor [${default_args}]: " monitor_args
    else
        monitor_name=${CUSTOM_MONITOR_NAME:-$default_name}
        monitor_args=${CUSTOM_MONITOR_ARGS:-$default_args}
    fi

    monitor_name=${monitor_name:-$default_name}
    
    monitor_user=${monitor_user:-$default_user}
    # Check if the user exists
    if ! id -u "$monitor_user" > /dev/null 2>&1; then
        log "Error: User $monitor_user does not exist." error
        return 1
    fi

    valid_units=("minutes" "hours" "days" "weeks")
    period_value=${period_value:-$default_period_value}
    period_unit=${period_unit:-$default_period_unit}
    if [[ ! " ${valid_units[*]} " =~ " $period_unit " ]]; then
        log "Invalid period unit. Exiting..." error
        return 1
    fi

    monitor_threshold=${monitor_threshold:-$default_threshold}
    monitor_direction=${monitor_direction:-$default_direction}
    monitor_args=${monitor_args:-$default_args}

    cp $script_path $CUSTOMBINDIR/
    monitor_script=$(basename $script_path)
    monitor=$CUSTOMBINDIR/$monitor_script
    chmod +x $monitor

    check_and_create_monitor "$monitor" "$monitor_name" $monitor_user "$period_value $period_unit" $monitor_threshold $monitor_direction "$monitor_args"
    if [ $? -eq 0 ]; then
        log "Installed $monitor..."
    fi
}

list_installed_monitors() {
    echo
    echo "Installed monitors:"

    index=1
    for monitor in "${INSTALLED_MONITORS[@]}"; do
        echo "$index. $monitor"
        index=$((index + 1))
    done

    echo "Hit enter to return to the main menu."
    read
    echo "Returning to main menu..."
}

list_available_monitors() {
    prompt_choice=$1
    echo "Available Monitors:"

    all_monitors=()
    for monitor in monitors/default/*; do
        monitor_name=$(grep -oP '# Name: \K.*' $monitor)
        all_monitors+=("$monitor_name")
    done

    index=1
    available_monitors=()
    echo
    for monitor in "${all_monitors[@]}"; do
        if [[ ! " ${INSTALLED_MONITORS[*]} " =~ " $monitor " ]]; then
            echo "$index. $monitor_name"
            available_monitors+=("$monitor_name")
            index=$((index + 1))
        fi
    done

    if [ $index -eq 1 ]; then
        echo
        echo "No uninstalled monitors found."
        echo "Returning to main menu..."
    else
        if [ "$prompt_choice" == "true" ]; then
            echo "$index. Back to main menu"

            read -p "Enter choice [1-$index]: " choice

            if [[ $choice -gt 0 && $choice -le ${#available_monitors[@]} ]]; then
                monitor_name=${available_monitors[$((choice - 1))]}
                monitor_script=$(get_script_name_from_monitor_name "$monitor_name")
                install_default_monitor $monitor_script
            elif [[ $choice -eq $index ]]; then
                echo "Returning to main menu..."
            else
                echo "Invalid choice, please try again." warn
            fi
        else
            echo "Hit enter to return to the main menu."
            read
            echo "Returning to main menu..."
        fi
    fi
}

delete_monitor() {
    monitor_name=$1
    monitor_script=$(grep "$monitor_name;" $MONITORREGISTER | awk -F\; '{print $2}')
    monitor_id=$(grep "$monitor_name;" $MONITORREGISTER | awk -F\; '{print $3}')

    crontab_entry=$(grep "dashboard $monitor_script .* # Dashboard" /etc/crontab)

    if [ -n "$crontab_entry" ]; then
        sed -i "\|$monitor_script .* # Dashboard|d" /etc/crontab
        log "Crontab entry for $monitor_name removed."
    else
        log "No crontab entry found for $monitor_name." warn
    fi

    rm $monitor_script
    sed -i "\|$monitor_script|d" $MONITORREGISTER

    delete_response=$(curl --silent --request DELETE \
        --url "https://dashboard.absoluteops.com/api/monitors/$monitor_id" \
        --header "Authorization: Bearer $API_KEY")

    if [ -z "$delete_response" ]; then
        log "Monitor $monitor_name with ID $monitor_id deleted from the API."
    else
        log "Failed to delete monitor $monitor_name from the API." warn
    fi
}

uninstall() {
    echo
    read -p "Are you sure you want to remove the software and all history? (y/n): " confirm
    if [[ $confirm == "y" || $confirm == "Y" ]]; then
        for monitor_name in "${INSTALLED_MONITORS[@]}"; do
            delete_monitor "$monitor_name"
        done

        log "Deleting the endpoint with the API..."
        response=$(curl --silent --request DELETE \
            --url "https://dashboard.absoluteops.com/api/endpoints/$ENDPOINT_ID" \
            --header "Authorization: Bearer $API_KEY" \
            --data-urlencode "cascade_delete=1")

        if [ -z "$response" ]; then
            log "Endpoint $ENDPOINT_ID deleted successfully."
            # Don't trust $ROOTDIR for this
            rm -rf /opt/dashboard
        else
            log "Failed to delete endpoint $ENDPOINT_ID. Response: $response" warn
        fi
    fi
}

show_menu() {
    echo
    echo "Select an action:"
    echo "1. List Monitors"
    echo "2. Install Monitors"
    echo "3. Delete Monitors"
    echo "4. Uninstall"
    echo "5. Exit"
}

list_monitors_menu() {
    echo
    echo "Select an action:"
    echo "1. List installed monitors"
    echo "2. List available monitors"
    echo "3. Back to main menu"
}

install_monitors_menu() {
    echo
    echo "Select an action:"
    echo "1. Install all default monitors"
    echo "2. Install a default monitor"
    echo "3. Install a custom monitor"
    echo "4. Back to main menu"
}

delete_monitor_menu() {
    echo
    echo "Select a monitor to delete:"

    index=1
    for monitor in "${INSTALLED_MONITORS[@]}"; do
        echo "$index. $monitor"
        index=$((index + 1))
    done
    echo "$index. Back to main menu"

    read -p "Enter choice [1-$index]: " choice

    if [[ $choice -gt 0 && $choice -le ${#INSTALLED_MONITORS[@]} ]]; then
        monitor_name=${INSTALLED_MONITORS[$((choice - 1))]}
        read -p "Are you sure you want to delete the monitor '$monitor_name'? (y/n): " confirm
        if [[ $confirm == "y" || $confirm == "Y" ]]; then
            delete_monitor "$monitor_name"
        else
            echo "Deletion cancelled."
        fi
    elif [[ $choice -eq $index ]]; then
        echo "Returning to main menu..."
    else
        echo "Invalid choice, please try again."
    fi
}

uninstall_dashboard() {
    log "Uninstalling the dashboard..."
    uninstall
    exit 0
}

check_root
prompt_api_key
check_endpoint_exists

if [[ "$UNINSTALL" == true ]]; then
    uninstall_dashboard
fi

log "No automation flag provided. Running interactive mode..."

check_dashboard_user
check_jq_installed
init
check_cron_service
get_installed_monitors

if [[ "$INSTALL_MONITORS" == true ]]; then
    log "Installing all default monitors."
    install_default_monitors
    exit 0
fi

while true; do
    show_menu
    read -p "Enter choice [1-5]: " choice
    case $choice in
        1)
            list_monitors_menu
            read -p "Enter choice [1-3]: " list_choice
            case $list_choice in
                1) list_installed_monitors ;;
                2) list_available_monitors ;;
                3) continue ;;
                *) echo "Invalid choice, please try again." ;;
            esac
            ;;
        2)
            install_monitors_menu
            read -p "Enter choice [1-4]: " install_choice
            case $install_choice in
                1) install_default_monitors ;;
                2) list_available_monitors true ;;
                3) install_custom_monitor ;;
                4) continue ;;
                *) echo "Invalid choice, please try again." ;;
            esac
            ;;
        3)
            delete_monitor_menu
            ;;
        4)
            uninstall
            ;;
        5) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid choice, please try again." ;;
    esac
done

