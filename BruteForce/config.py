import logging
from dataclasses import dataclass, field
from pathlib import Path

@dataclass
class BruteForceConfig:
    # 基础配置
    base_url: str = "http://192.1.1.55:801"
    login_path: str = "/eportal/InterFace.do"
    
    # 请求头
    headers: dict = field(default_factory=lambda: {
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Encoding": "gzip, deflate",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        "Content-Type": "application/x-www-form-urlencoded",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"
    })
    
    # 登录参数模板
    login_params: dict = field(default_factory=lambda: {
        "c": "ACSetting",
        "a": "Login", 
        "protocol": "http:",
        "hostname": "192.1.1.55",
        "iTermType": "0",
        "wlanuserip": None,  # 动态填充
        "wlanacip": "null",
        "wlanacname": "null",
        "mac": None,  # 动态填充
        "ip": "0.0.0.0",
        "enAdvert": "0",
        "queryACIP": "0",
        "jsVersion": "2.4.3",
        "loginMethod": "1"
    })
    
    # 请求体模板
    login_data: dict = field(default_factory=lambda: {
        "DDDDD": ",0,{}",  # 用户名占位符
        "upass": None,     # 密码占位符
        "R1": "0",
        "R2": "0",
        "R3": "0",
        "R6": "0",
        "para": "00",
        "0MKKey": "123456"
    })

def setup_logging():
    """配置日志系统"""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(str(Path(__file__).parent / 'logs/bruteforce.log')),
            logging.StreamHandler()
        ]
    )
