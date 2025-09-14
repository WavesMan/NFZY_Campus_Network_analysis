import subprocess
import logging
from typing import Dict, List, Optional

logger = logging.getLogger('NetworkChecker')

class NetworkChecker:
    def __init__(self, target_interfaces: List[str], host: str = "192.1.1.55", timeout: int = 2):
        self.target_interfaces = target_interfaces
        self.host = host
        self.timeout = timeout

    def check_connection(self) -> bool:
        """ 检查到指定主机的连通性 (ping)。 """
        try:
            result = subprocess.run(
                ["ping", "-c", "3", "-W", str(self.timeout), self.host],
                capture_output=True, text=True, check=False
            )
            if result.returncode == 0:
                logger.info(f"Global network connection to {self.host} is UP.")
                return True
            else:
                logger.warning(f"Global network connection to {self.host} is DOWN (ping exit code: {result.returncode}).")
                return False
        except FileNotFoundError:
            logger.error("Ping command not found. Please ensure 'ping' is installed.")
            return False
        except Exception as e:
            logger.error(f"An error occurred during network check: {e}")
            return False

    def get_network_info(self, interface_name: Optional[str] = None) -> Optional[Dict]:
        """ 获取指定接口的网络信息。 """
        if not self.target_interfaces:
            logger.error("No target interfaces configured.")
            return None
        
        target_if = interface_name if interface_name else self.target_interfaces[0]
        if not target_if:
            logger.error("Interface name is missing or invalid.")
            return None

        logger.info(f"Getting network info for interface: {target_if}")
        network_info = {
            "ip_addr": None, "gateway": None, "interface": target_if, "mac_addr": None
        }

        try:
            # --- 1. 尝试获取网关信息 ---
            route_result = subprocess.run(
                ["ip", "route", "show", "default"], capture_output=True, text=True, check=False
            )
            if route_result.returncode == 0 and route_result.stdout:
                route_line = route_result.stdout.strip().split('\n')[0]
                parts = route_line.split()
                if "default" in parts and "via" in parts and "dev" in parts:
                    try:
                        gateway_index = parts.index("via") + 1
                        network_info["gateway"] = parts[gateway_index]
                        route_interface = parts[parts.index("dev") + 1]
                        
                        # 如果传入了 interface_name，优先使用它
                        if interface_name:
                            network_info["interface"] = interface_name
                        # 否则，如果 route_info 提供了接口，使用它
                        elif route_interface:
                            network_info["interface"] = route_interface
                        else:
                            logger.warning("Could not determine interface from route info.")
                            
                        logger.info(f"Route info: Gateway={network_info['gateway']}, Interface from route={route_interface}")
                    except ValueError:
                        logger.warning("Could not parse route information for gateway/interface.")
                elif not interface_name: # 如果没有指定接口，并且路由信息不完整
                    network_info["interface"] = "phy1-sta1" # 备用默认值
                    logger.warning(f"Could not parse full route info. Using default interface: {network_info['interface']}")
            else:
                logger.warning("ip route show default command failed or returned empty output.")

            # --- 2. 获取 IP 地址 ---
            current_interface_for_ip = network_info["interface"]
            if current_interface_for_ip:
                ifconfig_result = subprocess.run(
                    ["ifconfig", current_interface_for_ip],
                    capture_output=True, text=True, check=False
                )
                if ifconfig_result.returncode == 0 and ifconfig_result.stdout:
                    found_ip = None
                    for line in ifconfig_result.stdout.split('\n'):
                        if "inet addr:" in line:
                            try:
                                found_ip = line.split("inet addr:")[1].split()[0]
                                logger.info(f"Found IP for {current_interface_for_ip}: {found_ip}")
                                break
                            except IndexError:
                                logger.warning(f"Could not parse IP address from line: {line}")
                                continue
                    
                    if found_ip:
                        network_info["ip_addr"] = found_ip
                    else:
                        # --- 关键修正：如果 ifconfig 成功但找不到 inet addr，记录错误并返回 None ---
                        logger.error(f"Could not find 'inet addr:' in ifconfig output for interface {current_interface_for_ip}.")
                        return None 
                else:
                    logger.warning(f"ifconfig command failed or returned empty output for interface {current_interface_for_ip}.")
                    return None 
            else:
                logger.error("Interface name could not be determined.")
                return None

            # --- 3. 获取 MAC 地址 ---
            if network_info["interface"]:
                ifconfig_result = subprocess.run(
                    ["ifconfig", network_info["interface"]],
                    capture_output=True, text=True, check=False
                )
                if ifconfig_result.returncode == 0 and ifconfig_result.stdout:
                    for line in ifconfig_result.stdout.split('\n'):
                        if "HWaddr" in line:
                            mac_address = line.split("HWaddr")[-1].strip()
                            network_info["mac_addr"] = mac_address.replace(":", "-")
                            logger.info(f"MAC address for {network_info['interface']}: {network_info['mac_addr']}")
                            break
                else:
                    logger.warning(f"ifconfig command failed or returned empty output for MAC address retrieval on interface {network_info['interface']}.")
            
            # --- 4. 校验是否成功获取必要信息 ---
            if not network_info["ip_addr"]:
                logger.error(f"Final check: IP address is missing for interface {target_if}.")
                return None
            if not network_info["mac_addr"]:
                logger.error(f"Final check: MAC address is missing for interface '{target_if}'.")
                return None
            
            return network_info

        except FileNotFoundError as e:
            logger.error(f"Required command not found: {e.filename}.")
            return None
        except Exception as e:
            logger.error(f"An error occurred during network info retrieval for {target_if}: {e}")
            return None