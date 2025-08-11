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

