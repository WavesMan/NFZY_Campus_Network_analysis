import json
from typing import Dict, Optional
from dataclasses import dataclass
import logging

@dataclass
class LoginResult:
    success: bool
    username: str
    message: str
    raw_response: str
    status_code: int

class ResponseAnalyzer:
    def __init__(self):
        self.logger = logging.getLogger(__name__)
        
    def analyze_response(self, response_data: Dict) -> Optional[LoginResult]:
        """分析登录响应"""
        try:
            # 尝试解析JSON响应
            response_text = response_data.get("response", "")
            status_code = response_data.get("status_code", 0)
            username = response_data.get("username", "")
            
            try:
                data = json.loads(response_text)
                message = data.get("msg", "No message in response")
                success = data.get("result", "") == "success"
            except json.JSONDecodeError:
                # 非JSON响应，直接分析文本
                message = response_text
                success = "success" in response_text.lower()
            
            return LoginResult(
                success=success,
                username=username,
                message=message,
                raw_response=response_text,
                status_code=status_code
            )
            
        except Exception as e:
            self.logger.error(f"Error analyzing response: {str(e)}")
            return None

    def is_rate_limited(self, response: LoginResult) -> bool:
        """检查是否被限速"""
        return "too many requests" in response.message.lower()

    def is_account_locked(self, response: LoginResult) -> bool:
        """检查账号是否被锁定"""
        return "locked" in response.message.lower()
