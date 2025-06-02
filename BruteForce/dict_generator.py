import itertools
from typing import List
import logging
from pathlib import Path

class DictGenerator:
    def __init__(self):
        self.logger = logging.getLogger(__name__)
        
    def generate_phone_numbers(self, prefix: str, start: int, end: int) -> List[str]:
        """生成11位手机号字典"""
        num_len = 11 - len(prefix)  # 计算数字部分长度
        self.logger.info(f"Generating phone numbers: prefix={prefix}, range={start}-{end}")
        numbers = []
        for num in range(start, end + 1):
            phone = f"{prefix}{num:0{num_len}d}"  # 动态补零
            numbers.append(phone)
        return numbers
    
    def generate_passwords(self) -> List[str]:
        """生成常见密码字典"""
        common_passwords = [
            "123456", "password", "12345678", "qwerty",
            "123456789", "12345", "1234", "111111",
            "1234567", "dragon", "123123", "admin",
            "welcome", "monkey", "password1", "abc123"
        ]
        return common_passwords
    
    def save_to_file(self, data: List[str], filename: str):
        """保存字典到文件"""
        path = Path("BruteForce/dicts") / filename
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(data))
        self.logger.info(f"Saved dictionary to {path} with {len(data)} entries")

if __name__ == "__main__":
    import config
    config.setup_logging()
    
    generator = DictGenerator()
    
    # 示例：生成手机号字典
    phones = generator.generate_phone_numbers("138", 10000000, 10000099)  # 生成100个号码
    generator.save_to_file(phones, "phone_dict.txt")
    
    # 生成密码字典
    passwords = generator.generate_passwords()
    generator.save_to_file(passwords, "password_dict.txt")
