#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${red}请用 root 权限运行${plain}" && exit 1

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
else
    echo "无法检测系统版本" && exit 1
fi

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv5* | armv5) echo 'armv5' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv7* | armv7) echo 'armv7' ;;
    s390x) echo 's390x' ;;
    *) echo 'amd64' ;;
    esac
}

install_base() {
    case "${release}" in
    centos | almalinux | rocky | oracle)
        yum -y update && yum install -y wget curl tar tzdata
        ;;
    fedora)
        dnf -y update && dnf install -y wget curl tar tzdata
        ;;
    *)
        apt-get update && apt-get install -y wget curl tar tzdata
        ;;
    esac
}

install_s-ui() {
    # 从原作者 alireza0 的 releases 获取最新版本号
    last_version=$(curl -Ls "https://api.github.com/repos/alireza0/s-ui/releases/latest" \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [[ -z "$last_version" ]]; then
        # API 限速时回退到固定版本
        last_version="v1.4.1"
        echo -e "${yellow}无法获取最新版本，使用 ${last_version}${plain}"
    fi

    echo -e "${green}正在安装 s-ui ${last_version}${plain}"

    wget -N --no-check-certificate \
        -O /tmp/s-ui-linux-$(arch).tar.gz \
        "https://github.com/alireza0/s-ui/releases/download/${last_version}/s-ui-linux-$(arch).tar.gz"

    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载失败，请检查网络或 GitHub 访问${plain}"
        exit 1
    fi

    systemctl stop s-ui 2>/dev/null
    rm -rf /usr/local/s-ui
    mkdir -p /usr/local/s-ui
    tar -xzf /tmp/s-ui-linux-$(arch).tar.gz -C /usr/local/s-ui/
    rm -f /tmp/s-ui-linux-$(arch).tar.gz
    chmod +x /usr/local/s-ui/sui

    # 创建管理脚本
    wget -N --no-check-certificate \
        -O /usr/local/s-ui/s-ui.sh \
        "https://raw.githubusercontent.com/alireza0/s-ui/main/s-ui.sh"
    chmod +x /usr/local/s-ui/s-ui.sh
    ln -sf /usr/local/s-ui/s-ui.sh /usr/bin/s-ui

    # 复制 service 文件
    wget -N --no-check-certificate \
        -O /etc/systemd/system/s-ui.service \
        "https://raw.githubusercontent.com/alireza0/s-ui/main/s-ui.service"
    wget -N --no-check-certificate \
        -O /etc/systemd/system/sing-box.service \
        "https://raw.githubusercontent.com/alireza0/s-ui/main/sing-box.service"

    systemctl daemon-reload
    systemctl enable s-ui --now

    /usr/local/s-ui/sui migrate

    echo -e "${green}s-ui ${last_version} 安装完成！${plain}"
    echo ""
    echo -e "默认面板地址: ${green}http://你的IP:2095/app/${plain}"
    echo -e "默认用户名: ${green}admin${plain}"
    echo -e "默认密码: ${green}admin${plain}"
}

install_base
install_s-ui
