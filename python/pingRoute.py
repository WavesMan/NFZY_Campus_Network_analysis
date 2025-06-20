import subprocess
from concurrent.futures import ThreadPoolExecutor

def ping_ip(ip):
    try:
        result = subprocess.run(['ping', '-n', '3', '-w', '500', ip], 
                              capture_output=True, 
                              text=True,
                              check=False)
        return (ip, "TTL=" in result.stdout)
    except:
        return (ip, False)

if __name__ == "__main__":
    # 开始隔离
    print("\n" + "="*50)
    print("开始扫描 10.X.0.1 网段 (0-255)")
    print("="*50 + "\n")
    
    reachable_ips = []
    
    # 使用线程池但保持顺序
    with ThreadPoolExecutor(max_workers=30) as executor:
        futures = []
        for x in range(256):
            ip = f"10.{x}.0.1"
            futures.append(executor.submit(ping_ip, ip))
        
        # 按顺序处理结果
        for x, future in enumerate(futures):
            ip, reachable = future.result()
            if reachable:
                reachable_ips.append(ip)
                print(f"{ip.ljust(12)} ✔ 可达")
            else:
                print(f"{ip.ljust(12)} ✖ 无响应")
    
    # 结束隔离和汇总
    print("\n" + "="*50)
    print("扫描完成，可达路由汇总：")
    print("-"*50)
    for ip in sorted(reachable_ips, key=lambda x: tuple(map(int, x.split('.')[1:]))):
        print(f"• {ip}")
    print("="*50)
