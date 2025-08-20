#!/usr/bin/env python3
import os
import sys
import subprocess
import random
import socket

def get_local_ip():
    try:
        # Get the local IP address
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def random_str(length=6):
    return ''.join(random.choices("abcdefghijklmnopqrstuvwxyz0123456789", k=length))

def input_with_default(prompt, 默认):
    v = input(f"{prompt} (默认: {default}): ")
    return v.strip() or default

def install_socks5(ip, port, user, passwd):
    # 安装依赖
    os.system("pip install --quiet --upgrade pip")
    os.system("pip install --quiet python-socks5")
    # 写配置文件
    config = f"""
from python_socks5.server import Socks5Server

def main():
    server = Socks5Server(
        listen_host='{ip}',
        listen_port={port},
        username='{user}',
        password='{passwd}'
    )
    server.serve_forever()

if __name__ == '__main__':
    main()
"""
    with open("/usr/local/socks5_server.py", "w") as f:
        f.write(config)
    # 创建服务脚本
    with open("/usr/local/socks5_start.sh", "w") as f:
        f.write("#!/bin/bash\nnohup python3 /usr/local/socks5_server.py &\n")
    os.system("chmod +x /usr/local/socks5_start.sh")
    # 启动服务
    os.system("/usr/local/socks5_start.sh")
    print("Socks5安装并启动成功！")

def uninstall_socks5():
    os.system("pkill -f socks5_server.py")
    os.system("rm -f /usr/local/socks5_server.py /usr/local/socks5_start.sh")
    print("Socks5已卸载！")

def modify_socks5():
    print("修改Socks5参数：")
    ip = get_local_ip()
    port = input_with_default("输入端口"， str(random.randint(10000, 20000)))
    user = input_with_default("输入用户名"， random_str())
    passwd = input_with_default("输入密码"， random_str())
    uninstall_socks5()
    install_socks5(ip, port, user, passwd)
    print_result(ip, port, user, passwd)

def print_result(ip, port, user, passwd):
    print(f"服务器IP:{ip} 端口:{port} 用户:{user} 密码:{passwd} https://t.me/socks?server={ip}&port={port}&user={user}&pass={passwd}")

def main_menu():
    ip = get_local_ip()
    port = str(random.randint(10000, 20000))
    user = random_str()
    passwd = random_str()
    while True:
        print("\n=== Socks5 管理脚本 ===")
        print("1. 安装 Socks5")
        print("2. 卸载 Socks5")
        print("3. 修改参数")
        print("0. 退出")
        choice = input("请选择功能[1/2/3/0]: ").strip()
        if choice == "1":
            print("请输入参数，可回车自动生成默认值：")
            port_in = input_with_default("输入端口", port)
            user_in = input_with_default("输入用户名", user)
            passwd_in = input_with_default("输入密码", passwd)
            install_socks5(ip, port_in, user_in, passwd_in)
            print_result(ip, port_in, user_in, passwd_in)
        elif choice == "2":
            uninstall_socks5()
        elif choice == "3":
            modify_socks5()
        elif choice == "0":
            print("退出。")
            sys.exit(0)
        else:
            print("无效选择，请重试。")

if __name__ == "__main__":
    if os.geteuid() != 0:
        print("请用root权限运行此脚本。")
        sys.exit(1)
    main_menu()
