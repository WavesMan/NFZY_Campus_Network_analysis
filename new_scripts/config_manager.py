import json
import os
import random
import logging
from typing import List, Dict, Optional, Tuple

logger = logging.getLogger('ConfigManager')

class AccountConfigManager:
    def __init__(self, config_path: str = "/etc/auto_login_accounts.json"):
        self.config_path = config_path
        self.accounts: List[Dict] = []
        self.account_state: Dict[str, int] = {} # username -> failure_count
        self.state_file_path = "/tmp/auto_login_account_state.json"
        self._load_config()
        self._load_state()

    def _load_config(self):
        """加载账号配置文件 (JSON格式)"""
        if not os.path.exists(self.config_path):
            logger.error(f"Account config file not found at {self.config_path}")
            self.accounts = []
            return

        try:
            with open(self.config_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                if isinstance(data, list):
                    self.accounts = data
                else:
                    logger.error(f"Invalid format in {self.config_path}. Expected a list of accounts.")
                    self.accounts = []
        except (json.JSONDecodeError, IOError) as e:
            logger.error(f"Error loading config file {self.config_path}: {e}")
            self.accounts = []

    def _load_state(self):
        """加载账号状态文件 (JSON格式)"""
        if not os.path.exists(self.state_file_path):
            logger.info("Account state file not found. Initializing.")
            for acc in self.accounts:
                if 'username' in acc:
                    self.account_state[acc['username']] = 0
            self._save_state()
            return

        try:
            with open(self.state_file_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                if isinstance(data, dict):
                    self.account_state = data
                else:
                    logger.error(f"Invalid format in state file {self.state_file_path}. Expected a dictionary.")
                    self.account_state = {}
        except (json.JSONDecodeError, IOError) as e:
            logger.error(f"Error loading state file {self.state_file_path}: {e}")
            self.account_state = {}

    def _save_state(self):
        """保存账号状态到文件"""
        try:
            with open(self.state_file_path, 'w', encoding='utf-8') as f:
                json.dump(self.account_state, f, indent=4)
        except IOError as e:
            logger.error(f"Error saving state file {self.state_file_path}: {e}")

    def get_accounts(self) -> List[Dict]:
        return self.accounts

    def get_next_account_to_try(self) -> Optional[Tuple[str, str]]:
        """ 选择下一个要尝试的账号。 """
        if not self.accounts:
            logger.error("No accounts available to try.")
            return None

        preferred_accounts = []
        fallback_accounts = []
        min_failure_count = float('inf')

        for acc in self.accounts:
            username = acc.get('username')
            if not username: continue

            failure_count = self.account_state.get(username, 0)

            if failure_count == 0:
                preferred_accounts.append(acc)
            else:
                if failure_count < min_failure_count:
                    min_failure_count = failure_count
                    fallback_accounts = [acc]
                elif failure_count == min_failure_count:
                    fallback_accounts.append(acc)

        chosen_account_data = None
        if preferred_accounts:
            logger.info("Selecting an unattempted account...")
            chosen_account_data = random.choice(preferred_accounts)
        elif fallback_accounts:
            logger.info(f"All accounts have failed at least once. Selecting from least failed (min failures: {min_failure_count})...")
            chosen_account_data = random.choice(fallback_accounts)
        else:
            logger.error("No accounts found to select.")
            return None

        username = chosen_account_data.get('username')
        password = chosen_account_data.get('password')
        return username, password

    def update_account_state(self, username: str, success: bool):
        """更新账号状态"""
        if not username: return

        if success:
            self.account_state[username] = 0
        else:
            current_count = self.account_state.get(username, 0)
            self.account_state[username] = current_count + 1
        self._save_state()