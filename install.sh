#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Fatal error: ${plain} Please run this script with root privilege \n " && exit 1

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Failed to check the system OS!" >&2
    exit 1
fi
echo "The OS release is: $release"

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    *) echo 'amd64' ;; # 默认尝试 amd64
    esac
}

install_base() {
    case "${release}" in
    centos | almalinux | rocky | oracle)
        yum -y update && yum install -y wget curl tar tzdata git make gcc
        ;;
    fedora)
        dnf -y update && dnf install -y wget curl tar tzdata git make gcc
        ;;
    *)
        apt-get update && apt-get install -y wget curl tar tzdata git make gcc
        ;;
    esac

    # 自动安装 Go 环境 (编译必须)
    if ! command -v go &> /dev/null; then
        echo -e "${yellow}Installing Go environment for building...${plain}"
        GO_VERSION="1.21.5"
        GO_ARCH=$(arch)
        wget -N https://golang.google.cn/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz
        rm -rf /usr/local/go && tar -C /usr/local -xzf go${GO_VERSION}.linux-${GO_ARCH}.tar.gz
        ln -sf /usr/local/go/bin/go /usr/local/bin/go
        rm -f go${GO_VERSION}.linux-${GO_ARCH}.tar.gz
    fi
}

config_after_install() {
    echo -e "${yellow}Migration... ${plain}"
    /usr/local/s-ui/sui migrate
    
    echo -e "${yellow}Install/update finished! For security it's recommended to modify panel settings ${plain}"
    read -p "Do you want to continue with the modification [y/n]? ": config_confirm
    if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
        echo -e "Enter the ${yellow}panel port${plain}:"
        read config_port
        echo -e "Enter the ${yellow}panel path${plain}:"
        read config_path
        
        params=""
        [ -z "$config_port" ] || params="$params -port $config_port"
        [ -z "$config_path" ] || params="$params -path $config_path"
        /usr/local/s-ui/sui setting ${params}

        read -p "Do you want to change admin credentials [y/n]? ": admin_confirm
        if [[ "${admin_confirm}" == "y" || "${admin_confirm}" == "Y" ]]; then
            read -p "Please set up your username:" config_account
            read -p "Please set up your password:" config_password
            /usr/local/s-ui/sui admin -username ${config_account} -password ${config_password}
        fi
    fi
}

prepare_services() {
    # 写入 systemd 服务文件，防止 Unit s-ui.service does not exist 报错
    cat > /etc/systemd/system/s-ui.service <<EOF
[Unit]
Description=s-ui service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/s-ui/
ExecStart=/usr/local/s-ui/sui
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

install_s-ui() {
    INSTALL_DIR="/usr/local/s-ui"
    # 请确保这里的链接是你自己 Fork 后的仓库地址
    REPO="https://github.com/szhfans/s-ui.git"

    if [ ! -d "$INSTALL_DIR" ]; then
        git clone $REPO $INSTALL_DIR
    else
        cd $INSTALL_DIR && git fetch --all && git reset --hard origin/main
    fi

    cd $INSTALL_DIR
    echo -e "${yellow}Building s-ui from source... this may take a few minutes${plain}"
    
    # 核心修复：执行编译
    # 假设你的项目主文件在根目录或有 Makefile，如果没有 Makefile，直接 go build
    if [ -f "Makefile" ]; then
        make build
    else
        go build -o sui main.go
    fi

    if [ ! -f "$INSTALL_DIR/sui" ]; then
        echo -e "${red}Build failed! Please check if the source code is complete.${plain}"
        exit 1
    fi

    chmod +x $INSTALL_DIR/sui $INSTALL_DIR/s-ui.sh
    ln -sf $INSTALL_DIR/s-ui.sh /usr/bin/s-ui

    prepare_services
    config_after_install

    systemctl enable s-ui --now
    echo -e "${green}s-ui installation finished!${plain}"
}

echo -e "${green}Executing...${plain}"
install_base
install_s-ui

