#!/bin/bash

# DeepSeek分布式部署环境初始化脚本
# 适用于Ubuntu 20.04 LTS

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "请不要使用root用户运行此脚本"
        exit 1
    fi
}

# 更新系统包
update_system() {
    log_info "更新系统包..."
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl wget git vim htop tree unzip
}

# 配置时区
setup_timezone() {
    log_info "配置时区为Asia/Shanghai..."
    sudo timedatectl set-timezone Asia/Shanghai
}

# 配置主机名和hosts
setup_hostname() {
    local node_type=$1
    local node_ip=$2
    
    log_info "配置主机名: deepseek-$node_type"
    sudo hostnamectl set-hostname deepseek-$node_type
    
    # 配置hosts文件
    sudo tee -a /etc/hosts << EOF

# DeepSeek Cluster Nodes
192.168.1.10    deepseek-master
192.168.2.11    deepseek-worker1  
192.168.2.12    deepseek-worker2
EOF
}

# 安装Docker
install_docker() {
    log_info "安装Docker..."
    
    # 卸载旧版本
    sudo apt remove -y docker docker-engine docker.io containerd runc || true
    
    # 安装依赖
    sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    # 添加Docker官方GPG密钥
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # 添加Docker仓库
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # 安装Docker Engine
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # 将当前用户添加到docker组
    sudo usermod -aG docker $USER
    
    # 配置Docker daemon
    sudo mkdir -p /etc/docker
    sudo tee /etc/docker/daemon.json << EOF
{
    "registry-mirrors": [
        "https://docker.mirrors.ustc.edu.cn",
        "https://hub-mirror.c.163.com"
    ],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "storage-driver": "overlay2"
}
EOF
    
    # 启动Docker服务
    sudo systemctl enable docker
    sudo systemctl start docker
    
    log_info "Docker安装完成"
}

# 安装Docker Compose
install_docker_compose() {
    log_info "安装Docker Compose..."
    
    # 下载最新版本的Docker Compose
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    
    # 添加执行权限
    sudo chmod +x /usr/local/bin/docker-compose
    
    # 创建软链接
    sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    log_info "Docker Compose安装完成"
}

# 安装K3s (仅在主节点)
install_k3s_master() {
    log_info "在主节点安装K3s..."
    
    # 安装K3s server
    curl -sfL https://get.k3s.io | sh -s - server \
        --write-kubeconfig-mode 644 \
        --node-name deepseek-master \
        --bind-address 0.0.0.0 \
        --advertise-address $(hostname -I | awk '{print $1}') \
        --disable traefik \
        --disable servicelb
    
    # 等待K3s启动
    sleep 30
    
    # 获取node token
    sudo cat /var/lib/rancher/k3s/server/node-token > /tmp/k3s-token
    chmod 644 /tmp/k3s-token
    
    # 配置kubectl
    mkdir -p $HOME/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    
    log_info "K3s主节点安装完成"
    log_info "Node Token: $(cat /tmp/k3s-token)"
}

# 安装K3s (工作节点)
install_k3s_worker() {
    local master_ip=$1
    local node_token=$2
    
    log_info "在工作节点安装K3s..."
    
    if [[ -z "$master_ip" || -z "$node_token" ]]; then
        log_error "需要提供主节点IP和Token"
        exit 1
    fi
    
    # 安装K3s agent
    curl -sfL https://get.k3s.io | K3S_URL=https://$master_ip:6443 K3S_TOKEN=$node_token sh -
    
    log_info "K3s工作节点安装完成"
}

# 安装Python和pip
install_python() {
    log_info "安装Python 3.9和pip..."
    
    sudo apt install -y python3.9 python3.9-dev python3-pip python3.9-venv
    
    # 创建软链接
    sudo ln -sf /usr/bin/python3.9 /usr/bin/python
    
    # 升级pip
    python -m pip install --upgrade pip
    
    # 安装常用Python包
    pip install requests pyyaml jinja2 kubernetes
    
    log_info "Python环境安装完成"
}

# 安装NVIDIA驱动和CUDA (如果有GPU)
install_nvidia_driver() {
    log_info "检查GPU并安装NVIDIA驱动..."
    
    # 检查是否有NVIDIA GPU
    if lspci | grep -i nvidia > /dev/null; then
        log_info "检测到NVIDIA GPU，安装驱动..."
        
        # 添加NVIDIA仓库
        wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-keyring_1.0-1_all.deb
        sudo dpkg -i cuda-keyring_1.0-1_all.deb
        sudo apt update
        
        # 安装NVIDIA驱动
        sudo apt install -y nvidia-driver-470
        
        # 安装CUDA Toolkit
        sudo apt install -y cuda-toolkit-11-7
        
        # 安装NVIDIA Container Toolkit
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
        curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
        
        sudo apt update
        sudo apt install -y nvidia-container-toolkit
        
        # 重启Docker服务
        sudo systemctl restart docker
        
        log_warn "GPU驱动安装完成，建议重启系统"
    else
        log_info "未检测到NVIDIA GPU，跳过驱动安装"
    fi
}

# 配置防火墙
setup_firewall() {
    log_info "配置防火墙规则..."
    
    # 安装ufw
    sudo apt install -y ufw
    
    # 重置防火墙规则
    sudo ufw --force reset
    
    # 默认策略
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # 允许SSH
    sudo ufw allow 22/tcp
    
    # 允许K3s相关端口
    sudo ufw allow 6443/tcp  # K3s API server
    sudo ufw allow 10250/tcp # Kubelet API
    sudo ufw allow 8472/udp  # Flannel VXLAN
    
    # 允许应用端口
    sudo ufw allow 8000/tcp  # API服务
    sudo ufw allow 80/tcp    # HTTP
    sudo ufw allow 443/tcp   # HTTPS
    
    # 启用防火墙
    sudo ufw --force enable
    
    log_info "防火墙配置完成"
}

# 创建工作目录
create_directories() {
    log_info "创建工作目录..."
    
    # 创建数据目录
    sudo mkdir -p /data/{models,logs,config,cache}
    sudo chown -R $USER:$USER /data
    
    # 创建项目目录
    mkdir -p $HOME/{deepseek,scripts,configs}
    
    log_info "目录创建完成"
}

# 配置系统优化参数
optimize_system() {
    log_info "优化系统参数..."
    
    # 优化内核参数
    sudo tee -a /etc/sysctl.conf << EOF

# DeepSeek优化参数
vm.max_map_count=262144
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
net.core.netdev_max_backlog=5000
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_keepalive_time=1200
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_tw_recycle=1
net.ipv4.ip_local_port_range=10000 65000
net.ipv4.tcp_max_tw_buckets=5000
EOF
    
    # 应用内核参数
    sudo sysctl -p
    
    # 优化文件描述符限制
    sudo tee -a /etc/security/limits.conf << EOF

# DeepSeek优化
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535  
* hard nproc 65535
EOF
    
    log_info "系统优化完成"
}

# 主函数
main() {
    local node_type=""
    local master_ip=""
    local node_token=""
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --type)
                node_type="$2"
                shift 2
                ;;
            --master-ip)
                master_ip="$2"
                shift 2
                ;;
            --token)
                node_token="$2"
                shift 2
                ;;
            *)
                log_error "未知参数: $1"
                echo "用法: $0 --type [master|worker] [--master-ip IP] [--token TOKEN]"
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$node_type" ]]; then
        log_error "请指定节点类型: --type [master|worker]"
        exit 1
    fi
    
    log_info "开始初始化DeepSeek部署环境..."
    log_info "节点类型: $node_type"
    
    # 执行初始化步骤
    check_root
    update_system
    setup_timezone
    setup_hostname $node_type
    install_docker
    install_docker_compose
    install_python
    install_nvidia_driver
    setup_firewall
    create_directories
    optimize_system
    
    # 根据节点类型安装K3s
    if [[ "$node_type" == "master" ]]; then
        install_k3s_master
    elif [[ "$node_type" == "worker" ]]; then
        if [[ -z "$master_ip" || -z "$node_token" ]]; then
            log_error "工作节点需要提供 --master-ip 和 --token 参数"
            exit 1
        fi
        install_k3s_worker $master_ip $node_token
    fi
    
    log_info "环境初始化完成！"
    log_warn "建议重启系统以确保所有配置生效"
    
    # 显示后续步骤
    echo ""
    log_info "后续步骤:"
    echo "1. 重启系统: sudo reboot"
    echo "2. 验证Docker: docker --version"
    echo "3. 验证K3s: kubectl get nodes"
    echo "4. 运行模型部署脚本"
}

# 执行主函数
main "$@" 