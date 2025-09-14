import time
import logging
import sys
import os
import subprocess
import json
from typing import List, Dict, Optional

# --- Import required modules ---
# Ensure these modules are in the same directory or in Python's path
from config_manager import AccountConfigManager
from network_checker import NetworkChecker
from auth_client import CampusAuthClient

# --- Configuration ---
SCRIPT_DIR = "/opt/scripts" # Base directory for scripts and configs
CONFIG_FILE = "/etc/auto_login_accounts.json"
STATE_FILE = "/tmp/auto_login_account_state.json"
LOG_FILE = "/var/log/auto_login.log"
LOCK_FILE = "/var/run/auto_login.pid"

# --- Authentication Server Details ---
AUTH_SERVER_HOST = "192.1.1.55"
AUTH_SERVER_PORT = 801
JS_VERSION = "2.4.3"

# --- Network Checking Details ---
PING_HOST = "192.1.1.55"
PING_TIMEOUT = 2

# --- Timing ---
RETRY_INTERVAL_CONNECTED = 600 # 10 minutes
RETRY_INTERVAL_FAILED = 300    # 5 minutes

# --- Network Interface Configuration ---
# !!! 请根据实际情况修改此列表 !!!
# 确认 phy1-sta0 和 phy1-sta1 是否都需要认证，并且它们有有效的 IP 地址
TARGET_INTERFACES = ["phy1-sta1", "phy1-sta0"] 

# --- Logging Configuration ---
# Set root logger level to DEBUG to capture all logs from modules
logging.basicConfig(
    level=logging.DEBUG, # Set to DEBUG to see detailed logs
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE, encoding='utf-8'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('MainApp')

# --- Global variables for network parameters ---
# Defined here so auth_client can access it. Ensure consistency.
global_network_params = {} 

# --- Module Instantiation ---
try:
    config_manager = AccountConfigManager(config_path=CONFIG_FILE)
    if not config_manager.get_accounts():
        logger.error(f"No accounts found in {CONFIG_FILE}. Please check the file and its format.")
        # sys.exit(1) # Optional: exit if no accounts
except Exception as e:
    logger.exception(f"Failed to initialize AccountConfigManager: {e}")
    sys.exit(1)

try:
    # Instantiate NetworkChecker, passing the target interfaces list
    network_checker = NetworkChecker(target_interfaces=TARGET_INTERFACES, host=PING_HOST, timeout=PING_TIMEOUT)
except Exception as e:
    logger.exception(f"Failed to initialize NetworkChecker: {e}")
    sys.exit(1)

try:
    # Instantiate AuthClient, passing the NetworkChecker instance
    auth_client = CampusAuthClient(
        auth_server_host=AUTH_SERVER_HOST,
        auth_server_port=AUTH_SERVER_PORT,
        js_version=JS_VERSION,
        network_checker=network_checker
    )
except Exception as e:
    logger.exception(f"Failed to initialize CampusAuthClient: {e}")
    sys.exit(1)

# --- Lock File Management ---
def is_running() -> bool:
    if os.path.exists(LOCK_FILE):
        try:
            with open(LOCK_FILE, 'r') as f:
                pid = int(f.read().strip())
                if os.path.exists(f"/proc/{pid}"):
                    logger.warning(f"Lock file {LOCK_FILE} found, PID {pid} is running. Exiting.")
                    return True
                else:
                    logger.warning(f"Lock file {LOCK_FILE} found but PID {pid} is not running. Removing stale lock file.")
                    os.remove(LOCK_FILE)
        except (IOError, ValueError, OSError) as e:
            logger.warning(f"Could not read or validate lock file {LOCK_FILE}: {e}. Removing stale lock file.")
            try: os.remove(LOCK_FILE)
            except OSError: pass
    return False

def create_lock_file():
    try:
        with open(LOCK_FILE, 'w') as f:
            f.write(str(os.getpid()))
        logger.info(f"Lock file created: {LOCK_FILE} with PID {os.getpid()}")
    except IOError as e:
        logger.error(f"Failed to create lock file {LOCK_FILE}: {e}")
        sys.exit(1)

def remove_lock_file():
    if os.path.exists(LOCK_FILE):
        try:
            with open(LOCK_FILE, 'r') as f:
                pid_in_file = int(f.read().strip())
            if pid_in_file == os.getpid():
                os.remove(LOCK_FILE)
                logger.info("Lock file removed.")
            else:
                logger.warning(f"Lock file {LOCK_FILE} contains PID {pid_in_file}, but current PID is {os.getpid()}. Not removing.")
        except (IOError, ValueError, OSError) as e:
            logger.warning(f"Failed to remove lock file {LOCK_FILE}: {e}")

# --- Main Loop Logic ---
def main_loop():
    logger.info("Starting continuous monitoring loop for multiple interfaces...")
    while True:
        # 1. 检查全局网络连通性
        if network_checker.check_connection():
            logger.info("Global network appears connected. Monitoring...")
            time.sleep(RETRY_INTERVAL_CONNECTED)
            continue

        # --- 网络断开，尝试登录 ---
        logger.warning("Global network appears disconnected. Attempting to log in for all target interfaces...")

        if not TARGET_INTERFACES:
            logger.warning("No target interfaces specified. Skipping authentication.")
            time.sleep(RETRY_INTERVAL_FAILED)
            continue

        account_to_try = config_manager.get_next_account_to_try()
        if not account_to_try:
            logger.error("No accounts available to try. Exiting loop.")
            break

        username, password = account_to_try
        logger.info(f"Using account {username} for authentication.")

        successful_auth_count = 0
        for interface in TARGET_INTERFACES:
            logger.info(f"Attempting to authenticate interface: {interface}")
            # perform_login 现在接受 interface_name 参数
            login_successful = auth_client.perform_login(username, password, interface_name=interface)
            config_manager.update_account_state(username, login_successful)

            if login_successful:
                successful_auth_count += 1
            else:
                logger.warning(f"Login failed for interface {interface} with account: {username}.")

        if successful_auth_count == len(TARGET_INTERFACES):
            logger.info(f"All {len(TARGET_INTERFACES)} target interfaces authenticated successfully. Monitoring...")
            time.sleep(RETRY_INTERVAL_CONNECTED)
        else:
            logger.warning(f"Only {successful_auth_count}/{len(TARGET_INTERFACES)} interfaces authenticated successfully. Retrying in {RETRY_INTERVAL_FAILED} seconds.")
            time.sleep(RETRY_INTERVAL_FAILED)

def run_once():
    logger.info("Running login attempt once for all target interfaces...")
    
    if not TARGET_INTERFACES:
        logger.warning("No target interfaces specified. Skipping run-once.")
        return False
        
    all_successful = True
    num_interfaces_attempted = 0
    
    account_to_try = config_manager.get_next_account_to_try()
    if not account_to_try:
        logger.error("No accounts available to try.")
        return False

    username, password = account_to_try
    logger.info(f"Using account {username} for authentication.")

    for interface in TARGET_INTERFACES:
        logger.info(f"Attempting to authenticate interface: {interface}")
        login_successful = auth_client.perform_login(username, password, interface_name=interface)
        config_manager.update_account_state(username, login_successful)
        
        num_interfaces_attempted += 1
        if not login_successful:
            all_successful = False
            logger.warning(f"Login failed for interface {interface} with account: {username}.")
        else:
            logger.info(f"Login successful for interface {interface} with account: {username}.")

    if all_successful and num_interfaces_attempted > 0:
        logger.info("All target interfaces authenticated successfully.")
        return True
    elif num_interfaces_attempted > 0:
        logger.warning("Some interfaces failed to authenticate.")
        return False
    else:
        logger.error("No interfaces were attempted or no accounts available.")
        return False

# --- Main Entry Point ---
def main():
    if is_running():
        sys.exit(0)

    create_lock_file()
    logger.info("Auto login service started.")

    try:
        if len(sys.argv) > 1:
            mode = sys.argv[1]
            if mode == 'start-loop':
                main_loop()
            elif mode == 'run-once':
                run_once()
            else:
                logger.warning(f"Unknown mode '{mode}'. Defaulting to run-once.")
                run_once()
        else:
            logger.info("No mode specified, running login once.")
            run_once()

    except KeyboardInterrupt:
        logger.info("Service interrupted by user (KeyboardInterrupt).")
    except Exception as e:
        logger.exception(f"An unhandled exception occurred: {e}")
    finally:
        remove_lock_file()
        logger.info("Auto login service stopped.")

if __name__ == "__main__":
    main()