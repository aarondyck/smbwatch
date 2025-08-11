# smbwatch

`smbwatch` is a simple `systemd`-based service designed to monitor the memory usage of Samba processes and preemptively prevent out-of-memory issues by flushing the filesystem cache.

## 💡 The Problem

File servers, especially those running Samba, can sometimes experience performance degradation or even run out of memory due to aggressive caching. This is often caused by the Linux kernel holding a large amount of data in its page cache, which can consume available RAM. While this caching is generally a good thing, in some scenarios it can lead to instability. The `smbwatch` tool was created to address this specific problem by proactively running the `sync` command to flush the cache before it becomes a critical issue.

## ⚙️ How It Works

This project consists of four main components:

1. **`smbwatch.py`**: A Python script that uses the `psutil` library to calculate the total resident memory (RSS) of all running processes with names starting with "smb". It then compares this total against a configurable memory threshold.

2. **`smbwatch.conf`**: A configuration file where you can set the memory threshold in megabytes.

3. **`smbwatch.service`**: A `systemd` service file that tells the system how to run the Python script.

4. **`smbwatch.timer`**: A `systemd` timer that schedules the service to run periodically (every 5 minutes by default).

When the total Samba memory usage exceeds the configured threshold, the script executes the `sync` command, forcing a flush of the filesystem cache and freeing up memory. The service also logs its activity, including the memory usage of individual processes, to `/var/log/smbwatch.log`, and this log file is automatically rotated to prevent it from growing too large.

## 🚀 Installation

The easiest way to install this tool is to use the provided `setup.sh` bash script.

**Prerequisites:**

* `python3`

* `psutil` (`pip3 install psutil`)

1. Download the `setup.sh` script to your server.

2. Run the script with `sudo` permissions:
