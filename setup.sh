#!/bin/bash

# This script creates all the necessary files for the smbwatch service:
# - A Python script to monitor memory usage
# - A configuration file for the script
# - A systemd service file to run the script
# - A systemd timer file to schedule the service

# It requires root privileges to write to system directories.
if [ "$EUID" -ne 0 ]
  then echo "Please run as root or with sudo"
  exit
fi

# --- Removal functionality ---
# If the script is run with the --remove flag, it will uninstall the service.
if [ "$1" == "--remove" ]; then
    echo "Stopping and disabling the smbwatch service and timer..."
    systemctl stop smbwatch.timer smbwatch.service &> /dev/null
    systemctl disable smbwatch.timer smbwatch.service &> /dev/null

    echo "Reloading systemd daemon..."
    systemctl daemon-reload

    echo "Removing service files..."
    rm -f /usr/local/bin/smbwatch.py /etc/smbwatch.conf /etc/systemd/system/smbwatch.service /etc/systemd/system/smbwatch.timer

    echo "smbwatch service has been successfully removed."
    exit 0
fi

# --- Dependency and Input Validation ---

# Function to check for dependencies
check_dependency() {
    if ! command -v "$1" &> /dev/null
    then
        echo "Error: '$1' is not installed."
        echo "Please install it before running this script."
        exit 1
    fi
}

# Check for python3 and pip3
echo "Checking for required dependencies..."
check_dependency "python3"
check_dependency "pip3"

# Check for psutil Python library
if ! python3 -c "import psutil" &> /dev/null; then
    echo "The 'psutil' Python library is not installed."
    read -p "Would you like to install it now using pip3? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pip3 install psutil
        if ! python3 -c "import psutil" &> /dev/null; then
            echo "Error: Failed to install 'psutil'. Please install it manually."
            exit 1
        fi
    else
        echo "Installation of 'psutil' is required. Exiting."
        exit 1
    fi
fi

# Ask for memory threshold and validate input
while true; do
    read -p "Enter the maximum memory threshold for Samba in MB (e.g., 1024): " THRESHOLD
    if [[ "$THRESHOLD" =~ ^[0-9]+$ ]]; then
        break
    else
        echo "Invalid input. Please enter a positive integer."
    fi
done

echo "Dependencies and configuration confirmed."

# --- File Creation ---

echo "Creating Python service script: /usr/local/bin/smbwatch.py"

# Create the Python script
cat << 'EOF' > /usr/local/bin/smbwatch.py
#!/usr/bin/python3
# smbwatch.py

import os
import sys
import psutil
import configparser
import logging
from logging.handlers import RotatingFileHandler

# Set up logging to a rotating file
LOG_FILE = '/var/log/smbwatch.log'
LOG_MAX_BYTES = 10 * 1024 * 1024 # 10 MB
LOG_BACKUP_COUNT = 1

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        RotatingFileHandler(LOG_FILE, maxBytes=LOG_MAX_BYTES, backupCount=LOG_BACKUP_COUNT)
    ]
)

def get_smb_memory_usage():
    """
    Calculates the total resident set size (RSS) memory used by all 'smb' processes.
    Returns the memory usage in megabytes (MB) and a list of process details.
    """
    total_memory_mb = 0
    smb_processes = []
    # Iterate through all running processes
    for proc in psutil.process_iter(['name', 'memory_info']):
        # Check if the process name starts with 'smb'
        if proc.info.name.startswith('smb'):
            try:
                # Add the process's resident set size (RSS) to the total
                # psutil.Process.memory_info().rss is in bytes, so we convert to MB
                memory_mb = proc.info.memory_info.rss / (1024 * 1024)
                total_memory_mb += memory_mb
                smb_processes.append({'pid': proc.pid, 'name': proc.info.name, 'memory_mb': memory_mb})
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                # Handle potential errors if a process terminates or is inaccessible
                pass
    return total_memory_mb, smb_processes

def run_sync_command():
    """
    Executes the 'sync' command to flush file system caches.
    This is the core action triggered by the memory threshold.
    """
    logging.info("Memory usage exceeds threshold. Running 'sync' command...")
    try:
        os.system("sync")
        logging.info("'sync' command completed.")
    except Exception as e:
        logging.error(f"Error running 'sync' command: {e}")

def main():
    """
    Main function to read config, check memory, and take action.
    """
    config_path = "/etc/smbwatch.conf"

    # Check if the configuration file exists
    if not os.path.exists(config_path):
        logging.error(f"Configuration file not found at {config_path}")
        sys.exit(1)

    # Read configuration from the file
    config = configparser.ConfigParser()
    config.read(config_path)

    try:
        # Get the memory threshold from the config file. Convert to MB.
        threshold_mb = config.getint('smbwatch', 'memory_threshold_mb')
    except (configparser.NoSectionError, configparser.NoOptionError, ValueError) as e:
        logging.error(f"Error reading configuration: {e}")
        sys.exit(1)

    # Get the current memory usage of smb processes
    current_memory_mb, smb_processes = get_smb_memory_usage()
    
    # Log the details of each individual smb process
    for proc in smb_processes:
        logging.info(f"Process PID: {proc['pid']}, Name: {proc['name']}, Memory: {proc['memory_mb']:.2f} MB")

    # Calculate and log the threshold percentage
    if threshold_mb > 0:
        threshold_percentage = (current_memory_mb / threshold_mb) * 100
        logging.info(f"Current smb total memory usage: {current_memory_mb:.2f} MB ({threshold_percentage:.2f}% of threshold). Threshold: {threshold_mb} MB.")
    else:
        logging.info(f"Current smb total memory usage: {current_memory_mb:.2f} MB. Threshold: {threshold_mb} MB.")

    # Check if the current memory usage exceeds the threshold
    if current_memory_mb > threshold_mb:
        run_sync_command()
    else:
        logging.info("Memory usage is below the threshold. No action needed.")

if __name__ == "__main__":
    main()

EOF

# Make the Python script executable
chmod +x /usr/local/bin/smbwatch.py
echo "Python script is now executable."

echo "Creating configuration file: /etc/smbwatch.conf"

# Create the configuration file with the user-provided threshold
cat << EOF > /etc/smbwatch.conf
[smbwatch]
# This value is the memory threshold in MB (megabytes).
# When the combined memory usage of all 'smb' processes
# exceeds this value, the 'sync' command will be run.
memory_threshold_mb = $THRESHOLD
EOF

echo "Creating systemd service file: /etc/systemd/system/smbwatch.service"

# Create the systemd service file
cat << 'EOF' > /etc/systemd/system/smbwatch.service
# /etc/systemd/system/smbwatch.service

[Unit]
Description=Samba Memory Usage Watcher Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/smbwatch.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "Creating systemd timer file: /etc/systemd/system/smbwatch.timer"

# Create the systemd timer file
cat << 'EOF' > /etc/systemd/system/smbwatch.timer
# /etc/systemd/system/smbwatch.timer

[Unit]
Description=Run smbwatch service every 5 minutes

[Timer]
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF

echo "Reloading systemd daemon..."
# Reload the systemd daemon to recognize the new files
systemctl daemon-reload

echo "Enabling and starting the smbwatch timer..."
# Enable and start the timer
systemctl enable smbwatch.timer
systemctl start smbwatch.timer

echo "Setup complete! The smbwatch service is now running."
echo "You can check the status with: systemctl status smbwatch.timer"
echo "Or check the service logs with: journalctl -u smbwatch.service"
