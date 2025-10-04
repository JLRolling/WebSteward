# 🌐 Web Steward - NGINX Application Manager

Modern, interactive Bash script for managing multiple Python web applications with NGINX reverse proxy, systemd services, and firewall configuration.

## ✨ Features

- 🚀 **Multi-app management** - Create, switch between, and manage multiple web applications
- 🔒 **Automatic security** - UFW firewall configuration with app-specific ports
- ⚙️ **Systemd integration** - Automatic service creation and management
- 🌐 **NGINX reverse proxy** - Automatic configuration and SSL-ready setup
- 🐍 **Python environment** - Virtual environment management with requirements.txt support
- 💾 **Backup & restore** - Configuration backup and restore functionality
- 🎨 **Modern UI** - Colorful, interactive terminal interface with loading animations
- 🔧 **Port management** - Automatic port finding and conflict resolution

## 🛠 Requirements

- Ubuntu/Debian-based system
- Python 3.6+
- Bash 4.0+

## 📥 Installation

### One-line Install & Run

```bash
wget -qO- https://raw.githubusercontent.com/JLRolling/WebSteward/main/web_steward_setup.sh | bash
```

Or Download and Run Manually

```bash
# Download the script
wget https://raw.githubusercontent.com/JLRolling/WebSteward/main/web_steward_setup.sh

# Make executable
chmod +x web_steward_setup.sh

# Run
./web_steward_setup.sh
```
## 🚀 Quick Start
1. Run the script using the installation method above
2. Create your first app using option [1] → a from the menu
3. Run full setup using option [2] to configure NGINX, firewall, and services
4. Access your app at http://your-server-ip

## 📖 Usage
Managing Applications
- Use option [1] to create, import, switch, or delete applications
- Each app gets its own directory, virtual environment, and systemd service

## Full Setup
- Option [2] performs complete setup: dependencies, firewall, NGINX, services
- Automatically finds available ports and configures everything
- Service Management
- Option [7] to start, stop, restart, or check status of your app services
- Requirements.txt Support
- Place requirements.txt in your app directory
- The script will automatically install all dependencies during setup
- Use option [15] to manually install requirements

## Requirements.txt Example
```text
flask==2.3.3
gunicorn==21.2.0
requests==2.31.0
```
## 🗂 Project Structure
```text
~/web_stewart_apps/          # App configurations
~/nginx_app_<name>/          # App directories
  ├── app.py                 # Main application file
  ├── requirements.txt       # Python dependencies
  └── venv/                  # Virtual environment
/etc/nginx/sites-available/  # NGINX configurations
/etc/systemd/system/         # Systemd services
```

## 🔧 Configuration Files
- Master config: ~/web_stewart_master.conf
- App configs: ~/web_stewart_apps/<app-name>.conf
- Backups: Automatically created in home directory

## 🛡 Security Features
- Automatic UFW firewall configuration
- App isolation with separate ports
- Non-root execution with sudo privileges
- Secure file permissions

## 🐛 Troubleshooting
**Common Issues**
- Port already in use: Script automatically finds alternative ports

- Permission denied: Script handles sudo privileges automatically

- NGINX not starting: Check logs with sudo systemctl status nginx

- App not accessible: Verify firewall allows HTTP traffic: sudo ufw status

**Logs & Debugging**
- App logs: sudo journalctl -u nginx_app_<name>

- NGINX logs: sudo tail -f /var/log/nginx/<app-name>.error.log

- Systemd: sudo systemctl status nginx_app_<name>

## 🔄 Updates
The script includes:

- System package updates (option [3])
- Python package updates (option [4])
- Configuration backup/restore (options [10], [11])
