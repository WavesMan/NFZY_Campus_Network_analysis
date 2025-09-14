import requests
import logging
import json
import os
import sys
import base64
from urllib.parse import urlencode, quote_plus, parse_qs, urlparse
from network_checker import NetworkChecker
from requests.adapters import HTTPAdapter
import subprocess
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger('AuthClient')

# --- Global variables for network parameters ---
# This dictionary will be used to store network info captured during redirects
# It's managed globally for simplicity. Make sure it's defined in main.py or here.
global_network_params = {} 

class CampusAuthClient:
    def __init__(self, auth_server_host: str, auth_server_port: int, js_version: str, network_checker: 'NetworkChecker'):
        self.auth_server_host = auth_server_host
        self.auth_server_port = auth_server_port
        self.js_version = js_version
        self.network_checker = network_checker
        self.auth_login_url_base = f"http://{auth_server_host}:{auth_server_port}/eportal/?c=ACSetting&a=Login"
        self.referer = f"http://{auth_server_host}/"
        self.login_timeout = 10
        self.ping_timeout = 2 # Timeout for the ping check

    def _get_network_info_for_auth(self, interface_name: str) -> Optional[Dict]:
        """ 获取认证所需的网络信息，针对指定的接口。 """
        network_info = self.network_checker.get_network_info(interface_name=interface_name)
        if not network_info:
            logger.error(f"Failed to get network info for interface {interface_name}.")
            return None
        return network_info

    def _decode_error_msg(self, encoded_msg: str) -> str:
        """尝试解码 ErrorMsg (Base64 或 URL decode)"""
        if not encoded_msg: return ""
        try:
            decoded_bytes = base64.b64decode(encoded_msg)
            return decoded_bytes.decode('utf-8', errors='ignore')
        except (base64.binascii.Error, UnicodeDecodeError):
            try:
                from urllib.parse import unquote
                return unquote(encoded_msg)
            except Exception:
                return encoded_msg

    def _parse_redirect_url(self, redirect_url: str) -> Tuple[bool, str]:
        """ 解析重定向 URL，提取 RetCode, ErrorMsg，并判断登录状态。 """
        logger.info(f"Parsing redirect URL: {redirect_url}")
        
        # --- 修正：处理相对路径的重定向 URL ---
        if redirect_url.startswith("?"):
            base_redirect_url = f"http://{self.auth_server_host}:80/{redirect_url.lstrip('?')}"
            logger.debug(f"Constructed full redirect URL: {base_redirect_url}")
        else:
            base_redirect_url = redirect_url
        # --- 修正结束 ---

        try:
            parsed_url = urlparse(base_redirect_url)
            query_params = parse_qs(parsed_url.query)

            ret_code = query_params.get("RetCode", [""])[0]
            error_msg_encoded = query_params.get("ErrorMsg", [""])[0]
            wlanuserip = query_params.get("wlanuserip", [""])[0]
            
            if wlanuserip: # 模拟保存网络参数
                global global_network_params 
                global_network_params["wlanuserip"] = wlanuserip
                logger.info(f"Captured network parameters from redirect: wlanuserip={wlanuserip}")

            decoded_error_msg = self._decode_error_msg(error_msg_encoded)
            logger.debug(f"Parsed RetCode: '{ret_code}', Raw ErrorMsg: '{error_msg_encoded}', Decoded ErrorMsg: '{decoded_error_msg}'")

            if not ret_code and not error_msg_encoded:
                logger.info("Redirect URL has no RetCode or ErrorMsg, assuming success.")
                return True, "登录成功"

            if ret_code:
                message = f"RetCode: {ret_code}"
                if ret_code == "2": # 终端IP已经在线
                    message = "终端IP已经在线"
                    logger.info(message)
                    return True, message
                elif ret_code == "998":
                    message = f"账号或密码错误 - {decoded_error_msg}" if decoded_error_msg else "账号或密码错误"
                elif ret_code == "0" or ret_code == "1":
                    message = f"AC认证失败: {decoded_error_msg}" if decoded_error_msg else "AC认证失败"
                elif ret_code == "3": message = "系统繁忙，请稍后再试"
                elif ret_code == "4": message = "发生未知错误，请稍后重试"
                elif ret_code == "5": message = "REQ_CHALLENGE失败，请联系AC确认"
                elif ret_code == "6": message = "REQ_CHALLENGE超时，请联系AC确认"
                elif ret_code == "7": message = "Radius认证失败"
                elif ret_code == "8": message = "Radius认证超时"
                elif ret_code == "9": message = "Radius下线失败"
                elif ret_code == "10": message = "Radius下线超时"
                elif ret_code == "11": message = "发生其他错误，请稍后重试"
                else: message = f"AC认证失败 (RetCode: {ret_code}) - {decoded_error_msg}" if decoded_error_msg else f"AC认证失败 (RetCode: {ret_code})"

                logger.warning(message)
                if ret_code not in ["2"]:
                    return False, message
            
            if decoded_error_msg:
                logger.warning(f"No RetCode, but found ErrorMsg: {decoded_error_msg}")
                if "密码错误" in decoded_error_msg or "password error" in decoded_error_msg: return False, "密码错误"
                if "已在线" in decoded_error_msg or "already online" in decoded_error_msg: return False, "账号已在其他设备登录"
                if "系统繁忙" in decoded_error_msg: return False, "系统繁忙，请稍后再试"
                return False, f"登录失败: {decoded_error_msg}"

            logger.warning("No RetCode or clear ErrorMsg found in URL parameters. Will attempt to parse HTML response.")
            return False, "未知登录错误，请检查 HTML 响应"
        
        except Exception as e:
            logger.error(f"Error parsing redirect URL '{redirect_url}': {e}")
            return False, "解析重定向 URL 时出错"

    def _parse_html_response(self, html_content: str) -> Tuple[bool, str]:
        """ 尝试从 HTML 响应中提取登录状态和错误信息。 """
        logger.debug(f"Parsing HTML response. Content length: {len(html_content)}")
        html_preview = html_content[:500] if len(html_content) > 500 else html_content
        logger.debug(f"HTML response preview:\n{html_preview}")

        if "成功" in html_content or "online" in html_content or "RetCode=2" in html_content:
            logger.info("HTML response suggests login success.")
            return True, "登录成功"
        if "密码错误" in html_content: return False, "密码错误"
        if "账号或密码错误" in html_content: return False, "账号或密码错误"
        if "已在线" in html_content: return False, "账号已在其他设备登录"
        if "系统繁忙" in html_content: return False, "系统繁忙，请稍后再试"
        if "认证失败" in html_content: return False, "认证失败"
        if "Msg=01" in html_content: return False, "认证失败 (Msg=01)"
        if "Msg=02" in html_content: return False, "账号已在其他设备登录 (Msg=02)"
        if "Msg=03" in html_content: return False, "系统繁忙 (Msg=03)"

        logger.warning("Could not extract specific error from HTML response.")
        return False, "登录失败，无法解析响应"

    def _check_network_connectivity(self, host: str) -> bool:
        """ 检查到指定主机的连通性 (ping)。 """
        try:
            ping_result = subprocess.run(
                ["ping", "-c", "3", "-W", str(self.ping_timeout), host],
                capture_output=True, text=True, check=False
            )
            if ping_result.returncode == 0:
                logger.info(f"Network connectivity check to {host} successful.")
                return True
            else:
                logger.warning(f"Network connectivity check to {host} failed (ping exit code: {ping_result.returncode}).")
                return False
        except FileNotFoundError:
            logger.error("Ping command not found. Cannot verify network connectivity.")
            return False
        except Exception as e:
            logger.error(f"Error during network connectivity check: {e}")
            return False

    def perform_login(self, username: str, password: str, interface_name: str) -> bool:
        """ 执行一次认证登录，针对指定的接口，并进行网络连通性验证。 """
        network_info = self._get_network_info_for_auth(interface_name=interface_name)
        if not network_info:
            logger.error(f"Failed to get network info for interface {interface_name}, cannot proceed with login.")
            return False

        ip_addr = network_info.get("ip_addr")
        mac_addr = network_info.get("mac_addr")

        if not ip_addr or not mac_addr:
            logger.error(f"Network info incomplete for {interface_name} after retrieval. IP: {ip_addr}, MAC: {mac_addr}. Cannot proceed.")
            return False

        # --- 构造 URL 查询参数 ---
        query_params = {
            "protocol": "http:", # Use http: directly, not encoded
            "hostname": self.auth_server_host,
            "iTermType": "1",
            "wlanuserip": ip_addr,
            "wlanacip": "null",
            "wlanacname": "null",
            "mac": mac_addr,
            "ip": ip_addr, # Use the actual IP address obtained for the interface
            "enAdvert": "0",
            "queryACIP": "0",
            "jsVersion": self.js_version,
            "loginMethod": "1"
        }

        # --- 构造 POST Body 参数 ---
        encoded_username_ddddd = f"%2C0%2C{quote_plus(username)}"
        post_data_raw = {
            "DDDDD": encoded_username_ddddd,
            "upass": password,
            "R1": "0", "R2": "0", "R3": "0", "R6": "0",
            "para": "00",
            "0MKKey": "123456",
            "buttonClicked": "",
            "redirect_url": "",
            "err_flag": "",
            "username": "",
            "password": "",
            "user": "",
            "cmd": "",
            "Login": "",
            "v6ip": ""
        }
        post_data = urlencode(post_data_raw)

        # --- 修正 URL 拼接 ---
        parsed_base_url = urlparse(self.auth_login_url_base)
        existing_query = parse_qs(parsed_base_url.query)
        for key, value in query_params.items():
            existing_query[key] = [value]
        new_query_string = urlencode(existing_query, doseq=True)
        request_url = parsed_base_url._replace(query=new_query_string).geturl()
        # --- 修正结束 ---

        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Content-Type": "application/x-www-form-urlencoded",
            "Referer": self.referer,
        }

        logger.info(f"Attempting login for interface {interface_name} with username: {username}")
        logger.debug(f"Request URL for {interface_name}: {request_url}")
        logger.debug(f"POST Data for {interface_name}: DDDDD={encoded_username_ddddd}&upass=********")

        try:
            session = requests.Session()
            
            # --- 定义内部类 CustomHTTPAdapter ---
            class CustomHTTPAdapter(HTTPAdapter):
                def __init__(self, network_checker_instance, target_interface_name):
                    self.network_checker = network_checker_instance
                    self.interface_name = target_interface_name
                    super().__init__()
                    logger.debug(f"CustomHTTPAdapter initialized for interface: {target_interface_name}")

                def init_poolmanager(self, connections, maxsize, block=False, **pool_kwargs):
                    source_address = None
                    try:
                        # 确保 network_checker 实例可用
                        logger.debug(f"CustomHTTPAdapter.init_poolmanager called for interface: {self.interface_name}")
                        logger.debug(f"Network checker instance available: {self.network_checker is not None}")
                        
                        if self.network_checker and self.interface_name:
                            logger.debug(f"Getting network info for interface: {self.interface_name}")
                            iface_info = self.network_checker.get_network_info(interface_name=self.interface_name)
                            logger.debug(f"Network info retrieved: {iface_info}")
                            
                            if iface_info and iface_info.get("ip_addr"):
                                source_ip = iface_info["ip_addr"]
                                source_address = (source_ip, 0) # Port 0 lets the system choose
                                logger.info(f"Setting source_address for connection pool: {source_address} for interface {self.interface_name}")
                            else:
                                logger.error(f"Could not get IP address for interface {self.interface_name} to set source_address. iface_info: {iface_info}")
                        else:
                            logger.error(f"Network checker or interface name is missing. network_checker: {self.network_checker}, interface_name: {self.interface_name}")
                    except Exception as e:
                        logger.error(f"Error preparing source_address for interface {self.interface_name}: {e}")
                    
                    if source_address:
                        pool_kwargs['source_address'] = source_address
                        logger.debug(f"Source address set in pool kwargs: {source_address}")
                    else:
                        logger.warning("No source address set, using default network interface")
                    
                    super().init_poolmanager(connections, maxsize, block, **pool_kwargs)
            # --- CustomHTTPAdapter 定义结束 ---

            adapter = CustomHTTPAdapter(network_checker_instance=self.network_checker, target_interface_name=interface_name) # Pass both network_checker and interface name
            session.mount('http://', adapter)
            
            response = session.post(
                request_url, headers=headers, data=post_data,
                timeout=self.login_timeout, allow_redirects=False
            )
            
            status_code = response.status_code
            logger.info(f"Initial response status code for {interface_name}: {status_code}")

            redirect_location = response.headers.get("Location")
            refresh_header = response.headers.get("Refresh")
            response_text = ""

            auth_success = False
            auth_message = "未知错误"

            if redirect_location:
                logger.info(f"Location header found for {interface_name}: {redirect_location}")
                auth_success, message = self._parse_redirect_url(redirect_location)
                auth_message = message
            elif refresh_header:
                logger.info(f"Found Refresh header for {interface_name}: {refresh_header}")
                redirect_url_from_refresh = ""
                if "url=" in refresh_header:
                    url_start_index = refresh_header.find("url=")
                    redirect_url_from_refresh = refresh_header[url_start_index + 4:].strip()
                elif "URL=" in refresh_header:
                    url_start_index = refresh_header.find("URL=")
                    redirect_url_from_refresh = refresh_header[url_start_index + 4:].strip()

                if redirect_url_from_refresh:
                    final_success, message = self._parse_redirect_url(redirect_url_from_refresh)
                    auth_success = final_success
                    auth_message = message
            
            # --- 处理 200 OK 响应 ---
            if status_code == 200:
                response_text = response.text
                logger.info(f"Received 200 OK response for {interface_name}.")
                auth_success, message = self._parse_html_response(response_text)
                auth_message = message
            # --- 处理其他非 200 状态码，如果重定向未处理 ---
            elif not auth_success: # If no successful redirect was detected and status is not 200
                logger.error(f"Request failed with status code {status_code} for {interface_name}")
                auth_success = False
                auth_message = f"HTTP Error {status_code}"
                try: logger.error(f"Response body: {response.text[:500]}...")
                except Exception: logger.error("Could not retrieve response body for error details.")

            # --- 最终判断 ---
            if auth_success:
                logger.info(f"Authentication steps passed for {interface_name}. Verifying network connectivity...")
                if self._check_network_connectivity(self.auth_server_host):
                    logger.info(f"Network connectivity check successful for {interface_name}.")
                    return True # 认证和连通性都成功
                else:
                    logger.warning(f"Network connectivity check failed for {interface_name}. Reporting login failure.")
                    return False # 认证成功但网络不通，算作失败
            else:
                # 认证步骤本身就失败了
                logger.warning(f"Authentication process failed for {interface_name}. Reason: {auth_message}")
                return False

        except requests.exceptions.Timeout:
            logger.error(f"Login request timed out for {interface_name}.")
            return False
        except requests.exceptions.RequestException as e:
            logger.error(f"An error occurred during login request for {interface_name}: {e}")
            if hasattr(e, 'response') and e.response is not None:
                logger.error(f"Response status code: {e.response.status_code}")
                try: logger.error(f"Response body: {e.response.text[:500]}...")
                except Exception: logger.error("Could not retrieve response body for error details.")
            return False
        except Exception as e:
            logger.exception(f"An unexpected error occurred during login for {interface_name}: {e}")
            return False
