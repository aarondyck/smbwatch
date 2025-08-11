# smbwatch

`smbwatch` is a simple `systemd`-based service designed to monitor the memory usage of Samba processes and preemptively prevent out-of-memory issues by flushing the filesystem cache.

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

   ```
   sudo bash setup.sh
   
   
   ```

The script will automatically create the necessary files, set permissions, and enable and start the `systemd` timer.

## 📝 Configuration

You can customize the memory threshold by editing the `smbwatch.conf` file.

```
sudo nano /etc/smbwatch.conf


```

Inside, you will find the `memory_threshold_mb` option. Change this value to a number (in MB) that is appropriate for your system's resources and usage patterns.

```
[smbwatch]
memory_threshold_mb = 1024


```

## ✅ Monitoring

You can monitor the status and output of the service using `systemd` and `journalctl`:

* Check the status of the timer:

  ```
  systemctl status smbwatch.timer
  
  
  ```

* View the live logs of the service:

  ```
  journalctl -u smbwatch.service -f
  
  
  ```

* You can also directly inspect the log file:

  ```
  tail -f /var/log/smbwatch.log
  
  
  ```

## 📜 License

This project is licensed under the   GNU GENERAL PUBLIC LICENSE Version 3.
