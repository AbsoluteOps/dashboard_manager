#!/bin/bash

ROOTDIR=/opt/dashboard
BINDIR=$ROOTDIR/bin
LOGDIR=$ROOTDIR/log
ETCDIR=$ROOTDIR/etc
API_KEY=""
ENDPOINT_ID=""

declare -a INSTALLED_MONITORS
declare -a AVAILABLE_MONITORS

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script must be run as root. Exiting..."
        exit 1
    fi
}

init() {
    mkdir -p $BINDIR
    mkdir -p $LOGDIR
    mkdir -p $ETCDIR

    touch $ETCDIR/config.settings
    touch $LOGDIR/monitor.log

    chown dashboard $LOGDIR/monitor.log
}

check_dashboard_user() {
    if ! id -u dashboard >/dev/null 2>&1; then
        read -p "The 'dashboard' user does not exist. Do you want to create it? (y/n): " create_user
        if [ "$create_user" == "y" ]; then
            sudo useradd -r -s /usr/sbin/nologin -d $ROOTDIR dashboard
            echo "'dashboard' user created."
        else
            echo "User creation declined. Exiting..."
            exit 1
        fi
    fi
}

check_cron_service() {
    if systemctl list-unit-files | grep -q '^cron\.service'; then
        service_name="cron"
    elif systemctl list-unit-files | grep -q '^crond\.service'; then
        service_name="crond"
    else
        echo "No cron service found. Exiting..."
        exit 1
    fi

    if ! systemctl is-enabled $service_name >/dev/null 2>&1; then
        read -p "$service_name is not enabled. Do you want to enable it? (y/n): " enable_cron
        if [ "$enable_cron" == "y" ]; then
            sudo systemctl enable $service_name
            sudo systemctl start $service_name
            if ! systemctl is-active $service_name >/dev/null 2>&1; then
                echo "Failed to start $service_name. Exiting..."
                exit 1
            fi
            echo "$service_name enabled and started."
        else
            echo "$service_name not enabled. Exiting..."
            exit 1
        fi
    fi
}

prompt_api_key() {
    if [ -f $ETCDIR/api_key ]; then
        echo "Found an API key at $ETCDIR/api_key."
        API_KEY=$(cat $ETCDIR/api_key)
    else
        read -p "Please enter your API key: " API_KEY
        read -p "Do you want to save the API key? (y/n): " save_key
        if [ "$save_key" == "y" ]; then
            echo $API_KEY > $ETCDIR/api_key
            echo "API key saved to $ETCDIR/api_key."
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
            echo "Endpoint information updated successfully."
            echo "$new_system_info" > $ETCDIR/system_info
        else
            echo "Failed to update endpoint information. Exiting..."
            exit 1
        fi
    else
        echo "System information has not changed. No update needed."
    fi
}

get_script_name_from_monitor_name() {
    local monitor_name=$1
    local script_name=""

    crontab_entries=$(grep '# Dashboard' /etc/crontab)

    while IFS= read -r entry; do
        script_path=$(echo "$entry" | awk '{print $7}')

        if [ -f "$script_path" ]; then
            default_name=$(grep -oP '# Default name: \K.*' "$script_path")

            if [ "$default_name" == "$monitor_name" ]; then
                script_name=$script_path
                break
            fi
        fi
    done <<< "$crontab_entries"

    echo "$script_name"
}

check_endpoint_exists() {
    if [ -f $ETCDIR/endpoint_id ]; then
        ENDPOINT_ID=$(cat $ETCDIR/endpoint_id)
        if [[ $ENDPOINT_ID =~ ^[0-9]+$ ]]; then
            echo "Endpoint ID $ENDPOINT_ID already exists at $ETCDIR/endpoint_id."
            check_endpoint_info
            return
        else
            echo "Invalid endpoint ID found in $ETCDIR/endpoint_id. Proceeding with API check..."
        fi
    fi

    hostname=$(hostname)
    response=$(curl --silent --request GET \
        --url 'https://dashboard.absoluteops.com/api/endpoints/' \
        --header "Authorization: Bearer $API_KEY")

    if echo $response | grep -q "\"name\": \"$hostname\""; then
        echo "Endpoint with hostname $hostname already exists."
        ENDPOINT_ID=$(echo $response | jq -r ".data[] | select(.name == \"$hostname\") | .id")
        echo $ENDPOINT_ID > $ETCDIR/endpoint_id
        check_endpoint_info
    else
        read -p "No endpoint with hostname $hostname found. Do you want to create it? (y/n): " create_endpoint
        if [ "$create_endpoint" == "y" ]; then
            echo "Creating endpoint..."
            create_response=$(curl --silent --request POST \
                --url 'https://dashboard.absoluteops.com/api/endpoints' \
                --header "Authorization: Bearer $API_KEY" \
                --header 'Content-Type: multipart/form-data' \
                --form "name=$hostname")

            ENDPOINT_ID=$(echo $create_response | jq -r ".data.id")
            echo $ENDPOINT_ID > $ETCDIR/endpoint_id
            check_endpoint_info
            echo "Endpoint created with ID $ENDPOINT_ID."
        else
            echo "Endpoint creation declined. Exiting..."
            exit 1
        fi
    fi
}

get_installed_monitors() {
    crontab_entries=$(grep '# Dashboard' /etc/crontab)

    while IFS= read -r entry; do
        script_path=$(echo "$entry" | awk '{print $7}')
        if [ -f "$script_path" ]; then
            default_name=$(grep -oP '# Default name: \K.*' "$script_path")

            if [ -n "$default_name" ]; then
                INSTALLED_MONITORS+=("$default_name")
            fi
        fi
    done <<< "$crontab_entries"
}

install_crontab_entry() {
    monitor_script=$1
    monitor_id=$2
    monitor_code=$3
    monitor_user=$4
    period_unit=$5
    period_value=$6

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
            echo "Unsupported period unit: $period_unit. Skipping..."
            continue
            ;;
    esac

    # Add crontab entry with monitor code
    if ! grep -q "dashboard $BINDIR/$monitor_script .* # Dashboard" /etc/crontab; then
        echo "$cron_schedule $monitor_user $BINDIR/$monitor_script $monitor_code # Dashboard $monitor_id" >> /etc/crontab
    else
        echo "Crontab entry for $monitor_script already exists."
    fi
}

check_and_create_monitor() {
    monitor_name=$1
    monitor=$2

    default_name=$(grep -oP '# Name: \K.*' $monitor)
    default_user=$(grep -oP '# User: \K.*' $monitor)
    default_period=$(grep -oP '# Period: \K.*' $monitor)
    default_threshold=$(grep -oP '# Threshold: \K.*' $monitor)
    default_direction=$(grep -oP '# Direction: \K.*' $monitor)

    period_value=$(echo $default_period | grep -oP '\d+')
    period_unit=$(echo $default_period | grep -oP '\d+\K.*' | xargs)

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
            echo "Unsupported period unit: $period_unit. Skipping..."
            return 1
            ;;
    esac

    # Check if the monitor already exists using the API
    response=$(curl --silent --request GET \
        --url "https://dashboard.absoluteops.com/api/monitors/" \
        --header "Authorization: Bearer $API_KEY" \
        --data-urlencode "endpoint_id=$ENDPOINT_ID")

    if echo $response | grep -q "\"name\":\"$monitor_name\""; then
        monitor_details=$(echo "$response" | grep -oP '{"id":\d+.*?"name":"'"$monitor_name"'".*?}')
        monitor_id=$(echo "$monitor_details" | grep -oP '"id":\K\d+')
        monitor_code=$(echo "$monitor_details" | grep -oP '"code":"\K[^"]+')
    else
        # Create the monitor using the API
        create_response=$(curl --silent --request POST \
            --url 'https://dashboard.absoluteops.com/api/monitors' \
            --header "Authorization: Bearer $API_KEY" \
            --header 'Content-Type: multipart/form-data' \
            --form "name=$default_name" \
            --form "endpoint_id=$ENDPOINT_ID" \
            --form "run_interval=$period_value" \
            --form "run_interval_type=$period_unit" \
            --form "run_interval_grace=$grace_period" \
            --form "run_interval_grace_type=$grace_unit" \
            --form "monitor_breach_value=$default_threshold" \
            --form "monitor_breach_value_type=$default_direction")

        monitor_id=$(echo $create_response | jq -r '.data.id')

        if [ -n "$monitor_id" ] && [ "$monitor_id" != "null" ]; then
            # Query the monitor to get the code
            monitor_response=$(curl --silent --request GET \
                --url "https://dashboard.absoluteops.com/api/monitors/$monitor_id" \
                --header "Authorization: Bearer $API_KEY")

            monitor_code=$(echo $monitor_response | jq -r '.data.code')
        else
            echo "Failed to create monitor $monitor_name. Skipping..."
            return 1
        fi
    fi

    if [ -n "$monitor_code" ] && [ "$monitor_code" != "null" ]; then
        install_crontab_entry $monitor_script $monitor_id $monitor_code $default_user $period_unit $period_value
        return 0
    else
        echo "Failed to retrieve monitor code for $monitor_name. Skipping..."
        return 1
    fi
}

install_default_monitor() {
    monitor_name=$(grep -oP '# Default name: \K.*' $monitor)
    echo "Installing $monitor_name..."
    monitor_script=$(basename $monitor)

    # Check and create monitor if it doesn't exist
    check_and_create_monitor "$monitor_name" "$monitor"
    if [ $? -eq 0 ]; then
        cp $monitor $BINDIR/
        chmod +x $BINDIR/$monitor_script
    fi
    echo "Installed $monitor..."
}

install_default_monitors() {
    echo "Installing default monitors..."
    for monitor in monitors/default/*; do
        install_default_monitor $monitor
    done
}

install_custom_monitor() {
    echo "Installing a custom monitor..."
    # Add commands to install a custom monitor
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
    echo "Listing available monitors..."
    # Add commands to list available monitors
}

delete_monitor() {
    monitor_name=$1
    monitor_script=$(get_script_name_from_monitor_name "$monitor_name")

    crontab_entry=$(grep "dashboard $monitor_script .* # Dashboard" /etc/crontab)

    if [ -n "$crontab_entry" ]; then
        sed -i "\|$monitor_script .* # Dashboard|d" /etc/crontab
        echo "Crontab entry for $monitor_name removed."
    else
        echo "No crontab entry found for $monitor_name."
    fi

    response=$(curl --silent --request GET \
        --url "https://dashboard.absoluteops.com/api/monitors/" \
        --header "Authorization: Bearer $API_KEY" \
        --data-urlencode "endpoint_id=$ENDPOINT_ID")

    monitor_details=$(echo "$response" | grep -oP '{"id":\d+.*?"name":"'"$monitor_name"'".*?}')
    monitor_id=$(echo "$monitor_details" | grep -oP '"id":\K\d+')

    if [ -n "$monitor_id" ]; then
        delete_response=$(curl --silent --request DELETE \
            --url "https://dashboard.absoluteops.com/api/monitors/$monitor_id" \
            --header "Authorization: Bearer $API_KEY")

        if [ -z "$delete_response" ]; then
            echo "Monitor $monitor_name with ID $monitor_id deleted from the API."
        else
            echo "Failed to delete monitor $monitor_name from the API."
        fi
    else
        echo "No monitor found with the name $monitor_name in the API."
    fi
}

show_menu() {
    echo
    echo "Select an action:"
    echo "1. List Monitors"
    echo "2. Install Monitors"
    echo "3. Delete Monitors"
    echo "4. Exit"
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

check_root
init
check_dashboard_user
check_cron_service
prompt_api_key
check_endpoint_exists
get_installed_monitors

while true; do
    show_menu
    read -p "Enter choice [1-3]: " choice
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
                2) install_default_monitor ;;
                3) install_custom_monitor ;;
                4) continue ;;
                *) echo "Invalid choice, please try again." ;;
            esac
            ;;
        3)
            delete_monitor_menu
            ;;
        4) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid choice, please try again." ;;
    esac
done
