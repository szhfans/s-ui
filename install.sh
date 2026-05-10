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
    *) echo 'amd64' ;;
    esac
}

install_base() {
    apt-get update && apt-get install -y wget curl tar tzdata git make gcc

    # 安装 Go
    if ! command -v go &> /dev/null; then
        echo -e "${yellow}正在安装 Go...${plain}"
        GO_VERSION="1.21.5"
        wget -q https://golang.google.cn/dl/go${GO_VERSION}.linux-$(arch).tar.gz
        rm -rf /usr/local/go
        tar -C /usr/local -xzf go${GO_VERSION}.linux-$(arch).tar.gz
        ln -sf /usr/local/go/bin/go /usr/local/bin/go
        rm -f go${GO_VERSION}.linux-$(arch).tar.gz
    fi

    # 安装 Node.js（编译前端必须）
    if ! command -v node &> /dev/null; then
        echo -e "${yellow}正在安装 Node.js...${plain}"
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
    fi
}

build_and_install() {
    INSTALL_DIR="/usr/local/s-ui"
    BUILD_DIR="/tmp/s-ui-build"
    REPO="https://github.com/szhfans/s-ui.git"

    # 克隆源码
    rm -rf $BUILD_DIR
    echo -e "${yellow}正在克隆仓库...${plain}"
    git clone $REPO $BUILD_DIR
    cd $BUILD_DIR

    # 初始化子模块（关键步骤，原脚本缺失）
    git submodule update --init --recursive

    # 编译前端（关键步骤，原脚本缺失）
    echo -e "${yellow}正在编译前端...${plain}"
    cd frontend
    npm install
    npm run build
    cd ..

    # 把前端产物放到正确位置
    rm -rf web/html/*
    cp -R frontend/dist/ web/html/

    # 编译后端
    echo -e "${yellow}正在编译后端...${plain}"
    go build -o sui main.go

    if [ ! -f "sui" ]; then
        echo -e "${red}编译失败，请检查源码${plain}"
        exit 1
    fi

    # 部署
    mkdir -p $INSTALL_DIR
    cp sui $INSTALL_DIR/sui
    cp -r web $INSTALL_DIR/
    chmod +x $INSTALL_DIR/sui

    # 创建管理脚本软链
    [ -f "$BUILD_DIR/s-ui.sh" ] && cp $BUILD_DIR/s-ui.sh $INSTALL_DIR/ && chmod +x $INSTALL_DIR/s-ui.sh && ln -sf $INSTALL_DIR/s-ui.sh /usr/bin/s-ui
}

setup_service() {
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
    systemctl enable s-ui --now
}

config_after_install() {
    /usr/local/s-ui/sui migrate

    read -p "Do you want to change admin credentials [y/n]? :" confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        read -p "Please set up your username:" username
        read -p "Please set up your password:" password
        /usr/local/s-ui/sui admin -username $username -password $password
    fi
}

echo -e "${green}开始安装 s-ui...${plain}"
install_base
build_and_install
setup_service
config_after_install

echo -e "${green}安装完成！${plain}"
