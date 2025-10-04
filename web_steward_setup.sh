#!/bin/bash
# nginx_setup.sh - NGINX Application Manager 2.0
# Full-featured interactive script (pure Bash) with modern terminal UI
# - App creation, import, systemd, nginx, firewall (ufw), backup, restore
# - Modern UI: banner, dashboard, colored logs, loading animation
# Usage: ./nginx_setup.sh

set -euo pipefail

# Fix for Windows line endings if needed
if grep -q $'\r' "$0"; then
    echo "Converting Windows line endings to Unix..."
    sed -i 's/\r$//' "$0"
    echo "Please run the script again."
    exit 0
fi

########## Colors & Icons ##########
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;97m'
BOLD='\033[1m'
NC='\033[0m' # No Color

ICON_APP="📦"
ICON_PATH="📂"
ICON_SERVICE="⚙️"
ICON_PORT="🌐"
ICON_SERVER="🚀"
ICON_OK="✓"
ICON_WARN="⚠️"
ICON_ERR="✗"
ICON_EXIT="❌"

USER=$(whoami)

########## Global configuration (Nginx-oriented) ##########
APPS_CONFIG_DIR="$HOME/web_stewart_apps"
MASTER_CONFIG="$HOME/web_stewart_master.conf"

# Runtime vars (will be loaded from configs)
CURRENT_APP="default"
AVAILABLE_APPS=("default")
APP_NAME=""
APP_DIR=""
VENV_DIR=""
SERVICE_NAME=""
NGINX_CONFIG=""
SERVER_TYPE="gunicorn"
APP_PORT="5000"
SETUP_COMPLETED="false"

########## Utility logging ##########
log_info()    { echo -e "${GREEN}[${ICON_OK} INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[${ICON_WARN} WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[${ICON_ERR} ERROR]${NC} $1"; }
log_debug()   { echo -e "${BLUE}[DEBUG]${NC} $1"; }

########## Loading / animation ##########
_loading_pid=""
loading_animation() {
    local message="${1:-Working}"
    local duration=${2:-0} # seconds; if 0 -> runs until stop_loading called
    local chars="/-\|"
    printf "%s " "$message"
    i=0
    if [ "$duration" -eq 0 ]; then
        while :; do
            printf "\b${chars:i%4:1}"
            sleep 0.15
            ((i++))
        done &
        _loading_pid=$!
    else
        end=$((SECONDS+duration))
        while [ $SECONDS -lt $end ]; do
            printf "\b${chars:i%4:1}"
            sleep 0.15
            ((i++))
        done
        printf "\b "
    fi
}

stop_loading() {
    if [ -n "$_loading_pid" ]; then
        kill "$_loading_pid" >/dev/null 2>&1 || true
        wait "$_loading_pid" 2>/dev/null || true
        _loading_pid=""
        printf "\b "
    fi
    echo ""
}

########## Config load/save ##########
load_master_config() {
    if [ -f "$MASTER_CONFIG" ]; then
        # shellcheck source=/dev/null
        source "$MASTER_CONFIG"
    else
        CURRENT_APP="default"
        AVAILABLE_APPS=("default")
        mkdir -p "$APPS_CONFIG_DIR"
        save_master_config
    fi
}

save_master_config() {
    mkdir -p "$APPS_CONFIG_DIR"
    cat > "$MASTER_CONFIG" << EOF
CURRENT_APP="$CURRENT_APP"
AVAILABLE_APPS=(${AVAILABLE_APPS[@]})
APPS_CONFIG_DIR="$APPS_CONFIG_DIR"
EOF
    chmod 600 "$MASTER_CONFIG" || true
}

load_app_config() {
    local app_name=$1
    local app_config="$APPS_CONFIG_DIR/${app_name}.conf"
    if [ -f "$app_config" ]; then
        # shellcheck source=/dev/null
        source "$app_config"
    else
        APP_NAME="$app_name"
        APP_DIR="$HOME/nginx_app_${app_name}"
        VENV_DIR="$APP_DIR/venv"
        SERVICE_NAME="nginx_app_${app_name}"
        NGINX_CONFIG="/etc/nginx/sites-available/${SERVICE_NAME}"
        SERVER_TYPE="gunicorn"
        APP_PORT="5000"
        SETUP_COMPLETED="false"
        save_app_config "$app_name"
    fi
}

save_app_config() {
    local app_name=$1
    local app_config="$APPS_CONFIG_DIR/${app_name}.conf"
    cat > "$app_config" << EOF
APP_NAME="$APP_NAME"
APP_DIR="$APP_DIR"
VENV_DIR="$VENV_DIR"
SERVICE_NAME="$SERVICE_NAME"
NGINX_CONFIG="$NGINX_CONFIG"
SERVER_TYPE="$SERVER_TYPE"
APP_PORT="$APP_PORT"
SETUP_COMPLETED="$SETUP_COMPLETED"
EOF
    chmod 600 "$app_config" || true
}

########## Port helpers ##########
is_port_in_use() {
    local port=$1
    if sudo lsof -i :"$port" >/dev/null 2>&1 || sudo ss -tulpn 2>/dev/null | grep -q ":$port "; then
        return 0
    fi
    return 1
}

check_port() {
    local port=$1
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo "invalid"
        return 1
    fi
    if [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
        echo "range"
        return 1
    fi

    for app in "${AVAILABLE_APPS[@]}"; do
        if [ "$app" != "$CURRENT_APP" ]; then
            local cfg="$APPS_CONFIG_DIR/${app}.conf"
            if [ -f "$cfg" ]; then
                # shellcheck source=/dev/null
                source "$cfg"
                if [ "$APP_PORT" = "$port" ]; then
                    echo "used_by_other_app"
                    load_app_config "$CURRENT_APP"
                    return 1
                fi
                load_app_config "$CURRENT_APP"
            fi
        fi
    done

    if is_port_in_use "$port"; then
        echo "used"
        return 1
    fi

    echo "valid"
    return 0
}

find_available_port() {
    local port
    echo ""
    echo -e "${CYAN}=== Port Selection ===${NC}"
    echo "1) Default 5000"
    echo "2) Auto find 5000-5100"
    echo "3) Auto find 8000-8100"
    echo "4) Enter custom"
    read -rp "Choose (1-4): " choice
    case $choice in
        1) port=5000 ;;
        2)
            port=5000
            while [ "$port" -le 5100 ]; do
                [ "$(check_port "$port")" = "valid" ] && break
                ((port++))
            done
            ;;
        3)
            port=8000
            while [ "$port" -le 8100 ]; do
                [ "$(check_port "$port")" = "valid" ] && break
                ((port++))
            done
            ;;
        4)
            while :; do
                read -rp "Port (1024-65535): " p
                if [ "$(check_port "$p")" = "valid" ]; then
                    port=$p
                    break
                else
                    log_error "Port invalid or in use."
                fi
            done
            ;;
        *) log_warn "Invalid, using 5000"; port=5000 ;;
    esac
    echo "$port"
}

########## System helpers ##########
install_system_dependencies() {
    log_info "Installing system dependencies (python3-venv python3-pip nginx ufw unzip)..."
    loading_animation "Installing packages..." &
    _loading_pid=$!
    sudo apt update -y >/dev/null 2>&1 || true
    sudo apt install -y python3-venv python3-pip nginx ufw unzip >/dev/null 2>&1 || true
    stop_loading
    log_info "System dependencies ensured."
}

install_python_packages() {
    if [ ! -d "$VENV_DIR" ]; then
        log_error "Venv missing at $VENV_DIR"
        return 1
    fi
    # shellcheck disable=SC1090
    source "$VENV_DIR/bin/activate"
    log_info "Installing pip packages (gunicorn, flask)..."
    pip install --upgrade pip >/dev/null 2>&1 || true
    pip install gunicorn flask >/dev/null 2>&1 || true
    deactivate
    return 0
}

verify_python_installations() {
    if [ -f "$VENV_DIR/bin/gunicorn" ]; then
        return 0
    fi
    return 1
}

cleanup_existing_processes() {
    # Placeholder for custom cleanup logic
    log_debug "Cleanup: no-op"
}

########## Service & nginx config ##########
create_systemd_service() {
    local app_port=$1
    local svc="/etc/systemd/system/${SERVICE_NAME}.service"
    log_info "Creating systemd service ${SERVICE_NAME}.service"
    sudo bash -c "cat > $svc" << EOF
[Unit]
Description=Nginx Managed App: $APP_NAME
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$APP_DIR
Environment=PATH=$VENV_DIR/bin
ExecStart=$VENV_DIR/bin/gunicorn -w 3 -b 127.0.0.1:$app_port app:app
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo systemctl enable "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
    log_info "Systemd unit created & enabled (manual start recommended)."
}

configure_nginx() {
    local app_port=$1
    local site="/etc/nginx/sites-available/${SERVICE_NAME}"
    local enabled="/etc/nginx/sites-enabled/${SERVICE_NAME}"
    log_info "Creating nginx site for $SERVICE_NAME (proxy to 127.0.0.1:$app_port)"
    sudo bash -c "cat > $site" << EOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:$app_port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    access_log /var/log/nginx/${SERVICE_NAME}.access.log;
    error_log /var/log/nginx/${SERVICE_NAME}.error.log;
}
EOF
    sudo ln -sf "$site" "$enabled"
    sudo nginx -t >/dev/null 2>&1 || log_warn "nginx test returned issues"
    log_info "Nginx site created and enabled."
}

test_server() {
    local server_type=$1
    local port=$2
    log_info "Testing server for $APP_NAME (basic checks only)..."

    if [ -f "$APP_DIR/app.py" ]; then
        log_info "Found app.py — recommend starting with systemd/gunicorn for production."
        return 0
    else
        log_warn "No app.py found; runtime test skipped."
        return 1
    fi
}

create_app_files() {
    mkdir -p "$APP_DIR"
    if [ ! -f "$APP_DIR/app.py" ]; then
        cat > "$APP_DIR/app.py" << 'PY'
from flask import Flask
app = Flask(__name__)

@app.route("/")
def index():
    return "Hello from Nginx App Manager!"

if __name__ == "__main__":
    import os
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
PY
        log_info "Minimal Flask app template created at $APP_DIR/app.py"
    fi
}

fix_permissions_and_dependencies() {
    log_info "Fixing permissions and ensuring basic packages"
    sudo systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
    sudo chown -R "$USER":"$USER" "$APP_DIR" 2>/dev/null || true
    find "$APP_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || true
    find "$APP_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || true

    if [ -d "$VENV_DIR" ]; then
        # shellcheck disable=SC1090
        source "$VENV_DIR/bin/activate"
        pip install --no-cache-dir gunicorn flask >/dev/null 2>&1 || true
        deactivate
    fi
    log_info "Permissions and packages adjusted."
}

########## Application management ##########
switch_application() {
    while :; do
        clear
        print_banner
        echo -e "${CYAN}--- Manage Applications ---${NC}"
        for i in "${!AVAILABLE_APPS[@]}"; do
            local app="${AVAILABLE_APPS[$i]}"
            if [ "$app" = "$CURRENT_APP" ]; then
                echo -e "${GREEN}[$((i+1))] $app (current)${NC}"
            else
                echo "[$((i+1))] $app"
            fi
        done
        echo ""
        echo "a) Create new application"
        echo "i) Import existing application"
        echo "d) Delete application"
        echo "b) Back"
        read -rp "Choice: " ch
        case $ch in
            [0-9]*)
                local idx=$((ch-1))
                if [ $idx -ge 0 ] && [ $idx -lt ${#AVAILABLE_APPS[@]} ]; then
                    CURRENT_APP="${AVAILABLE_APPS[$idx]}"
                    save_master_config
                    load_app_config "$CURRENT_APP"
                    log_info "Switched to $CURRENT_APP"
                else
                    log_error "Invalid index"
                fi
                ;;
            a|A) create_new_application ;;
            i|I) import_existing_application ;;
            d|D) delete_application ;;
            b|B) break ;;
            *) log_error "Invalid option" ;;
        esac
        read -rp "Press Enter to continue..." _
    done
}

create_new_application() {
    clear
    print_banner
    echo -e "${CYAN}=== Create New Application ===${NC}"
    read -rp "App name (alphanumeric _ -): " new_app_name
    if [[ ! "$new_app_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Bad name"
        return 1
    fi
    if [[ " ${AVAILABLE_APPS[*]} " == *" $new_app_name "* ]]; then
        log_error "Already exists"
        return 1
    fi
    AVAILABLE_APPS+=("$new_app_name")
    CURRENT_APP="$new_app_name"
    save_master_config
    load_app_config "$new_app_name"
    mkdir -p "$APP_DIR"
    log_info "Creating venv..."
    python3 -m venv "$VENV_DIR" >/dev/null 2>&1 || true
    install_python_packages || true
    create_app_files
    save_app_config "$CURRENT_APP"
    log_info "App $CURRENT_APP created at $APP_DIR"
}

delete_application() {
    clear
    print_banner
    echo -e "${CYAN}=== Delete Application ===${NC}"
    for i in "${!AVAILABLE_APPS[@]}"; do
        echo "[$((i+1))] ${AVAILABLE_APPS[$i]}"
    done
    read -rp "Select number to delete: " sel
    if ! [[ "$sel" =~ ^[0-9]+$ ]]; then
        log_error "Invalid selection"
        return 1
    fi
    idx=$((sel-1))
    if [ $idx -lt 0 ] || [ $idx -ge ${#AVAILABLE_APPS[@]} ]; then
        log_error "Out of range"
        return 1
    fi
    local app_to_delete="${AVAILABLE_APPS[$idx]}"
    if [ "$app_to_delete" = "$CURRENT_APP" ]; then
        log_error "Cannot delete current app. Switch first."
        return 1
    fi
    read -rp "Confirm delete $app_to_delete (y/n): " -n 1 -r; echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cancelled"
        return 0
    fi
    local svc="nginx_app_${app_to_delete}"
    sudo systemctl stop "$svc" 2>/dev/null || true
    sudo systemctl disable "$svc" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/${svc}.service" 2>/dev/null || true
    sudo rm -f "/etc/nginx/sites-available/${svc}" 2>/dev/null || true
    sudo rm -f "/etc/nginx/sites-enabled/${svc}" 2>/dev/null || true
    rm -f "$APPS_CONFIG_DIR/${app_to_delete}.conf" 2>/dev/null || true
    rm -rf "$HOME/nginx_app_${app_to_delete}" 2>/dev/null || true
    unset 'AVAILABLE_APPS[$idx]'
    AVAILABLE_APPS=("${AVAILABLE_APPS[@]}")
    save_master_config
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl reload nginx 2>/dev/null || true
    log_info "Deleted $app_to_delete"
}

show_app_info() {
    echo -e "${BOLD}${ICON_APP} Application:${NC} ${GREEN}$CURRENT_APP${NC}   ${SETUP_COMPLETED:+${GREEN}✅ Setup: Done${NC}}"
    echo -e "${ICON_PATH} Path: ${CYAN}$APP_DIR${NC}"
    echo -e "${ICON_SERVICE} Service: ${CYAN}$SERVICE_NAME.service${NC}"
    echo -e "${ICON_PORT} Port: ${CYAN}$APP_PORT${NC} | ${ICON_SERVER} Server: ${CYAN}$SERVER_TYPE${NC}"
}

########## Import existing application ##########
import_existing_application() {
    clear
    print_banner
    echo -e "${CYAN}=== Import Existing Application ===${NC}"
    read -rp "Absolute path to existing app dir: " existing_path
    if [ -z "$existing_path" ] || [ ! -d "$existing_path" ]; then
        log_error "Directory not found"
        return 1
    fi
    local has_app=false
    [ -f "$existing_path/app.py" ] && has_app=true
    [ -f "$existing_path/wsgi.py" ] && has_app=true
    echo "Detected files:"
    [ -f "$existing_path/app.py" ] && echo " - app.py"
    [ -f "$existing_path/wsgi.py" ] && echo " - wsgi.py"
    read -rp "Name to register as (alphanumeric _ -): " import_name
    if [[ ! "$import_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid name"
        return 1
    fi
    if [[ " ${AVAILABLE_APPS[*]} " == *" $import_name "* ]]; then
        log_error "Name already exists"
        return 1
    fi
    read -rp "Server type (gunicorn/flask) [gunicorn]: " server_choice
    server_choice=${server_choice:-gunicorn}
    while :; do
        read -rp "Port to use [5000]: " port_choice
        port_choice=${port_choice:-5000}
        if [ "$(check_port "$port_choice")" = "valid" ]; then
            break
        else
            log_error "Port invalid or used."
        fi
    done
    AVAILABLE_APPS+=("$import_name")
    CURRENT_APP="$import_name"
    save_master_config
    APP_NAME="$import_name"
    APP_DIR="$existing_path"
    VENV_DIR="$APP_DIR/venv"
    SERVICE_NAME="nginx_app_${APP_NAME}"
    NGINX_CONFIG="/etc/nginx/sites-available/${SERVICE_NAME}"
    SERVER_TYPE="$server_choice"
    APP_PORT="$port_choice"
    SETUP_COMPLETED="true"
    save_app_config "$APP_NAME"
    log_info "Imported $APP_NAME -> $APP_DIR"
    read -rp "Create systemd service & nginx now? (y/n) [y]: " -n 1 -r; echo
    if [[ $REPLY =~ ^[Yy]$ || -z $REPLY ]]; then
        if [ ! -d "$VENV_DIR" ]; then
            log_info "Creating venv in app directory..."
            python3 -m venv "$VENV_DIR" >/dev/null 2>&1 || true
            install_python_packages || true
        fi
        create_systemd_service "$APP_PORT"
        configure_nginx "$APP_PORT"
        sudo systemctl start "${SERVICE_NAME}.service" 2>/dev/null || true
        sudo systemctl reload nginx 2>/dev/null || true
        log_info "systemd & nginx started for $APP_NAME"
    else
        log_info "Imported without starting systemd/nginx."
    fi
}

########## Full setup ##########
full_setup() {
    log_info "Starting full setup for $CURRENT_APP"
    cleanup_existing_processes
    APP_PORT=$(find_available_port)
    log_info "Selected port: $APP_PORT"
    save_app_config "$CURRENT_APP"
    install_system_dependencies
    setup_firewall "$APP_PORT"
    log_info "Preparing app dir: $APP_DIR"
    mkdir -p "$APP_DIR" "$APP_DIR/templates" "$APP_DIR/static/css" "$APP_DIR/static/js" "$APP_DIR/static/images"
    cd "$APP_DIR" || true
    if [ -d "$VENV_DIR" ]; then
        log_info "Removing existing venv..."
        rm -rf "$VENV_DIR" || true
    fi
    python3 -m venv "$VENV_DIR" >/dev/null 2>&1 || true
    install_python_packages || log_warn "Python package install had issues"
    fix_permissions_and_dependencies
    create_app_files
    if ! test_server "$SERVER_TYPE" "$APP_PORT"; then
        log_warn "Runtime quick-test failed or skipped"
    fi
    create_systemd_service "$APP_PORT"
    configure_nginx "$APP_PORT"
    sudo systemctl start nginx 2>/dev/null || true
    sudo systemctl start "${SERVICE_NAME}.service" 2>/dev/null || true
    SETUP_COMPLETED="true"
    save_app_config "$CURRENT_APP"
    log_info "Full setup complete for $CURRENT_APP"
}

########## Firewall ##########
setup_firewall() {
    local app_port=$1
    log_info "Configuring firewall for port $app_port"
    if ! command -v ufw &>/dev/null; then
        log_info "Installing ufw..."
        sudo apt update -y >/dev/null 2>&1 || true
        sudo apt install -y ufw >/dev/null 2>&1 || true
    fi
    sudo ufw --force reset >/dev/null 2>&1 || true
    sudo ufw default deny incoming >/dev/null 2>&1 || true
    sudo ufw default allow outgoing >/dev/null 2>&1 || true
    sudo ufw allow ssh >/dev/null 2>&1 || true
    sudo ufw allow 80/tcp >/dev/null 2>&1 || true
    sudo ufw allow 443/tcp >/dev/null 2>&1 || true
    for app in "${AVAILABLE_APPS[@]}"; do
        local cfg="$APPS_CONFIG_DIR/${app}.conf"
        if [ -f "$cfg" ]; then
            # shellcheck source=/dev/null
            source "$cfg"
            sudo ufw allow "$APP_PORT"/tcp comment "Nginx App: $app" >/dev/null 2>&1 || true
        fi
    done
    load_app_config "$CURRENT_APP"
    echo "y" | sudo ufw enable >/dev/null 2>&1 || true
    log_info "Firewall configured"
}

########## Nginx management ##########
nginx_management() {
    clear
    print_banner
    echo -e "${CYAN}--- Nginx Management ---${NC}"
    echo "1) Show nginx status"
    echo "2) Reload nginx"
    echo "3) Test nginx configuration"
    echo "4) List enabled sites"
    echo "5) List available sites"
    echo "6) Back"
    read -rp "Choice: " ch
    case $ch in
        1) sudo systemctl status nginx --no-pager --lines=10 || true ;;
        2) sudo systemctl reload nginx || true; log_info "Reloaded nginx" ;;
        3) if sudo nginx -t; then log_info "nginx test OK"; else log_error "nginx test failed"; fi ;;
        4) sudo ls -la /etc/nginx/sites-enabled/ 2>/dev/null || echo "No enabled sites" ;;
        5) sudo ls -la /etc/nginx/sites-available/ 2>/dev/null || echo "No available sites" ;;
        6) return ;;
        *) log_error "Invalid" ;;
    esac
    read -rp "Press Enter..." _
}

########## Misc admin ##########
update_system_packages() {
    log_info "Updating system packages..."
    loading_animation "Updating..." &
    _loading_pid=$!
    sudo apt update && sudo apt upgrade -y >/dev/null 2>&1 || true
    stop_loading
    log_info "System updated"
}

update_python_packages() {
    log_info "Updating python packages in venv (if present)"
    if [ -d "$VENV_DIR" ]; then
        # shellcheck disable=SC1090
        source "$VENV_DIR/bin/activate"
        pip list --outdated --format=freeze | cut -d = -f 1 | xargs -r pip install -U >/dev/null 2>&1 || true
        deactivate
        log_info "Python packages updated"
    else
        log_warning "Venv not present"
    fi
}

switch_server_mode() {
    read -rp "Server (gunicorn/flask) [gunicorn]: " choice
    choice=${choice:-gunicorn}
    SERVER_TYPE="$choice"
    save_app_config "$CURRENT_APP"
    log_info "Server type set to $SERVER_TYPE"
}

change_application_port() {
    read -rp "New port: " new_port
    if [ "$(check_port "$new_port")" = "valid" ]; then
        APP_PORT="$new_port"
        save_app_config "$CURRENT_APP"
        log_info "Port changed to $APP_PORT"
    else
        log_error "Port invalid or used"
    fi
}

service_management() {
    echo -e "${CYAN}--- Service Management (${SERVICE_NAME}.service) ---${NC}"
    echo "1) Start"
    echo "2) Stop"
    echo "3) Restart"
    echo "4) Status"
    echo "5) Back"
    read -rp "Choice: " ch
    case $ch in
        1) sudo systemctl start "${SERVICE_NAME}.service" || true ;;
        2) sudo systemctl stop "${SERVICE_NAME}.service" || true ;;
        3) sudo systemctl restart "${SERVICE_NAME}.service" || true ;;
        4) sudo systemctl status "${SERVICE_NAME}.service" --no-pager --lines=10 || true ;;
        5) return ;;
        *) log_error "Invalid" ;;
    esac
    read -rp "Press Enter..." _
}

firewall_management() {
    sudo ufw status verbose || true
    read -rp "Press Enter..." _
}

show_status_overview() {
    clear
    print_banner
    echo -e "${CYAN}=== Status Overview ===${NC}"
    echo "Available apps: ${AVAILABLE_APPS[*]}"
    echo ""
    for app in "${AVAILABLE_APPS[@]}"; do
        local cfg="$APPS_CONFIG_DIR/${app}.conf"
        if [ -f "$cfg" ]; then
            # shellcheck source=/dev/null
            source "$cfg"
            echo "- ${app}: dir=${APP_DIR} port=${APP_PORT} svc=${SERVICE_NAME} setup=${SETUP_COMPLETED}"
        else
            echo "- ${app}: no config"
        fi
    done
    read -rp "Press Enter..." _
}

backup_configuration() {
    local out="$HOME/nginx_apps_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    tar -czf "$out" "$APPS_CONFIG_DIR" "$MASTER_CONFIG" 2>/dev/null || true
    log_info "Backup saved to $out"
}

restore_configuration() {
    log_info "Restore: place backup tar.gz in home and extract manually:"
    echo "tar -xzf backupfile.tar.gz -C ~/"
}

########## UI: banner, menu, dashboard ##########
print_banner() {
    clear
    echo -e "${MAGENTA}┌────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${MAGENTA}│${NC}  ${BOLD}          🌀 WEB STEWARD${NC}               ${MAGENTA}│${NC}"
    echo -e "${MAGENTA}│${NC}        Multi-App NGINX Deployment & Management Tool ${MAGENTA}│${NC}"
    echo -e "${MAGENTA}└────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    # show small status
    show_app_info
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────────────${NC}"
}

print_menu() {
    echo ""
    echo -e "${BOLD}Menu:${NC}"
    echo -e "  ${BOLD}[1]${NC}  🔁  Manage Applications"
    echo -e "  ${BOLD}[2]${NC}  ⚙️  Full Setup (Current App)"
    echo -e "  ${BOLD}[3]${NC}  🧩  Update System Packages"
    echo -e "  ${BOLD}[4]${NC}  🐍  Update Python Packages"
    echo -e "  ${BOLD}[5]${NC}  🔄  Switch Server Mode"
    echo -e "  ${BOLD}[6]${NC}  🔌  Change Application Port"
    echo -e "  ${BOLD}[7]${NC}  🧰  Service Management"
    echo -e "  ${BOLD}[8]${NC}  🔥  Firewall Management"
    echo -e "  ${BOLD}[9]${NC}  📊  Status Overview"
    echo -e "  ${BOLD}[10]${NC} 💾  Backup Configuration"
    echo -e "  ${BOLD}[11]${NC} ♻️  Restore Configuration"
    echo -e "  ${BOLD}[12]${NC} 🩺  Fix Permissions"
    echo -e "  ${BOLD}[13]${NC} 🧪  Test Server"
    echo -e "  ${BOLD}[14]${NC} 🌍  Nginx Management"
    echo -e "  ${BOLD}[0]${NC}  ${ICON_EXIT}  Exit"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────────${NC}"
}

########## Main loop ##########
main() {
    if [ "$EUID" -eq 0 ]; then
        log_error "Do not run as root. Run as a normal user; script will call sudo when needed."
        exit 1
    fi
    load_master_config
    load_app_config "$CURRENT_APP"

    while :; do
        print_banner
        print_menu
        read -rp "Select option (0-14): " main_choice
        case $main_choice in
            1) switch_application ;;
            2) full_setup ;;
            3) update_system_packages ;;
            4) update_python_packages ;;
            5) switch_server_mode ;;
            6) change_application_port ;;
            7) service_management ;;
            8) firewall_management ;;
            9) show_status_overview ;;
            10) backup_configuration ;;
            11) restore_configuration ;;
            12) fix_permissions_and_dependencies ;;
            13) log_info "Testing..."; test_server "$SERVER_TYPE" "$APP_PORT" ;;
            14) nginx_management ;;
            0) log_info "Goodbye!"; exit 0 ;;
            *) log_error "Invalid option" ;;
        esac
        echo ""
        read -rp "Press Enter to return to menu..." _
    done
}

# Start
main