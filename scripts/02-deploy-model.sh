#!/bin/bash

# DeepSeek模型部署脚本
# 用于下载、部署和启动DeepSeek模型服务

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
MODEL_NAME="deepseek-coder-6.7b-instruct"
MODEL_PATH="/data/models/${MODEL_NAME}"
CACHE_DIR="/data/cache"
LOG_DIR="/data/logs"
DOCKER_IMAGE="deepseek-api:latest"
NAMESPACE="default"

# 华为云OBS配置
OBS_BUCKET="deepseek-models"
OBS_ENDPOINT="obs.cn-north-4.myhuaweicloud.com"

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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查依赖
check_dependencies() {
    log_step "检查依赖..."
    
    # 检查Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker未安装，请先运行环境初始化脚本"
        exit 1
    fi
    
    # 检查kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl未安装，请先安装Kubernetes客户端"
        exit 1
    fi
    
    # 检查Python
    if ! command -v python &> /dev/null; then
        log_error "Python未安装，请先运行环境初始化脚本"
        exit 1
    fi
    
    # 检查Git LFS
    if ! command -v git-lfs &> /dev/null; then
        log_info "安装Git LFS..."
        sudo apt update
        sudo apt install -y git-lfs
        git lfs install
    fi
    
    log_info "依赖检查完成"
}

# 创建必要目录
create_directories() {
    log_step "创建必要目录..."
    
    sudo mkdir -p ${MODEL_PATH}
    sudo mkdir -p ${CACHE_DIR}
    sudo mkdir -p ${LOG_DIR}
    sudo mkdir -p /data/config
    
    sudo chown -R $USER:$USER /data
    
    log_info "目录创建完成"
}

# 下载DeepSeek模型
download_model() {
    log_step "下载DeepSeek模型..."
    
    if [ -d "${MODEL_PATH}" ] && [ -f "${MODEL_PATH}/config.json" ]; then
        log_info "模型已存在，跳过下载"
        return 0
    fi
    
    # 方法1: 从Hugging Face下载
    if download_from_huggingface; then
        log_info "从Hugging Face下载模型成功"
        return 0
    fi
    
    # 方法2: 从华为云OBS下载
    if download_from_obs; then
        log_info "从华为云OBS下载模型成功"
        return 0
    fi
    
    # 方法3: 从ModelScope下载
    if download_from_modelscope; then
        log_info "从ModelScope下载模型成功"
        return 0
    fi
    
    log_error "所有下载方法都失败了"
    exit 1
}

# 从Hugging Face下载模型
download_from_huggingface() {
    log_info "尝试从Hugging Face下载模型..."
    
    # 安装huggingface-hub
    pip install huggingface-hub --upgrade
    
    # 设置镜像源
    export HF_ENDPOINT=https://hf-mirror.com
    
    # 下载模型
    python -c "
from huggingface_hub import snapshot_download
import os

model_id = 'deepseek-ai/deepseek-coder-6.7b-instruct'
local_dir = '${MODEL_PATH}'

try:
    snapshot_download(
        repo_id=model_id,
        local_dir=local_dir,
        local_dir_use_symlinks=False,
        resume_download=True
    )
    print('模型下载成功')
except Exception as e:
    print(f'下载失败: {e}')
    exit(1)
"
    
    return $?
}

# 从华为云OBS下载模型
download_from_obs() {
    log_info "尝试从华为云OBS下载模型..."
    
    # 检查OBS配置
    if [ -z "$HW_ACCESS_KEY" ] || [ -z "$HW_SECRET_KEY" ]; then
        log_warn "华为云访问密钥未配置，跳过OBS下载"
        return 1
    fi
    
    # 安装obsutil
    if ! command -v obsutil &> /dev/null; then
        log_info "安装obsutil..."
        wget https://obs-community.obs.cn-north-1.myhuaweicloud.com/obsutil/current/obsutil_linux_amd64.tar.gz
        tar -xzf obsutil_linux_amd64.tar.gz
        sudo mv obsutil_linux_amd64_*/obsutil /usr/local/bin/
        rm -rf obsutil_linux_amd64*
    fi
    
    # 配置obsutil
    obsutil config -i=${HW_ACCESS_KEY} -k=${HW_SECRET_KEY} -e=${OBS_ENDPOINT}
    
    # 下载模型
    obsutil cp obs://${OBS_BUCKET}/${MODEL_NAME}/ ${MODEL_PATH}/ -r -f
    
    return $?
}

# 从ModelScope下载模型
download_from_modelscope() {
    log_info "尝试从ModelScope下载模型..."
    
    # 安装modelscope
    pip install modelscope --upgrade
    
    # 下载模型
    python -c "
from modelscope import snapshot_download
import os

model_id = 'deepseek-ai/deepseek-coder-6.7b-instruct'
cache_dir = '${MODEL_PATH}'

try:
    snapshot_download(
        model_id=model_id,
        cache_dir=cache_dir,
        revision='master'
    )
    print('模型下载成功')
except Exception as e:
    print(f'下载失败: {e}')
    exit(1)
"
    
    return $?
}

# 验证模型完整性
verify_model() {
    log_step "验证模型完整性..."
    
    # 检查必要文件
    required_files=(
        "config.json"
        "tokenizer.json"
        "tokenizer_config.json"
        "pytorch_model.bin"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "${MODEL_PATH}/${file}" ]; then
            log_error "缺少必要文件: ${file}"
            return 1
        fi
    done
    
    # 检查模型大小
    model_size=$(du -sh ${MODEL_PATH} | cut -f1)
    log_info "模型大小: ${model_size}"
    
    # 测试模型加载
    log_info "测试模型加载..."
    python -c "
from transformers import AutoTokenizer, AutoModelForCausalLM
import torch

model_path = '${MODEL_PATH}'

try:
    tokenizer = AutoTokenizer.from_pretrained(model_path, trust_remote_code=True)
    print('Tokenizer加载成功')
    
    # 只在有GPU时加载模型
    if torch.cuda.is_available():
        model = AutoModelForCausalLM.from_pretrained(
            model_path,
            torch_dtype=torch.float16,
            device_map='auto',
            trust_remote_code=True
        )
        print('模型加载成功')
    else:
        print('无GPU，跳过模型加载测试')
        
except Exception as e:
    print(f'模型加载失败: {e}')
    exit(1)
"
    
    if [ $? -eq 0 ]; then
        log_info "模型验证成功"
        return 0
    else
        log_error "模型验证失败"
        return 1
    fi
}

# 构建Docker镜像
build_docker_image() {
    log_step "构建Docker镜像..."
    
    # 检查Dockerfile
    if [ ! -f "docker/deepseek-api/Dockerfile" ]; then
        log_error "Dockerfile不存在"
        exit 1
    fi
    
    # 构建镜像
    docker build -t ${DOCKER_IMAGE} -f docker/deepseek-api/Dockerfile .
    
    if [ $? -eq 0 ]; then
        log_info "Docker镜像构建成功"
    else
        log_error "Docker镜像构建失败"
        exit 1
    fi
}

# 部署到Kubernetes
deploy_to_kubernetes() {
    log_step "部署到Kubernetes..."
    
    # 检查集群连接
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到Kubernetes集群"
        exit 1
    fi
    
    # 创建命名空间
    kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # 创建ConfigMap
    kubectl apply -f kubernetes/deployment.yaml
    
    # 等待部署完成
    log_info "等待部署完成..."
    kubectl rollout status deployment/deepseek-master -n ${NAMESPACE} --timeout=600s
    kubectl rollout status deployment/deepseek-worker -n ${NAMESPACE} --timeout=600s
    
    # 检查Pod状态
    kubectl get pods -n ${NAMESPACE} -l app=deepseek
    
    log_info "Kubernetes部署完成"
}

# 启动本地服务
start_local_service() {
    log_step "启动本地服务..."
    
    # 创建docker-compose.yml
    cat > docker-compose.yml << EOF
version: '3.8'

services:
  deepseek-master:
    image: ${DOCKER_IMAGE}
    container_name: deepseek-master
    ports:
      - "8000:8000"
      - "9090:9090"
    environment:
      - NODE_TYPE=master
      - NODE_ROLE=coordinator
      - CLUSTER_ENABLED=true
      - MODEL_PATH=/data/models/${MODEL_NAME}
      - TENSOR_PARALLEL_SIZE=1
      - GPU_MEMORY_UTILIZATION=0.85
      - LOG_LEVEL=INFO
    volumes:
      - ${MODEL_PATH}:/data/models/${MODEL_NAME}:ro
      - ${CACHE_DIR}:/data/cache
      - ${LOG_DIR}:/data/logs
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    restart: unless-stopped
    
  deepseek-worker1:
    image: ${DOCKER_IMAGE}
    container_name: deepseek-worker1
    ports:
      - "8001:8000"
      - "9091:9090"
    environment:
      - NODE_TYPE=worker
      - NODE_ROLE=inference
      - CLUSTER_ENABLED=true
      - MASTER_NODE=deepseek-master:8000
      - MODEL_PATH=/data/models/${MODEL_NAME}
      - TENSOR_PARALLEL_SIZE=1
      - GPU_MEMORY_UTILIZATION=0.85
      - LOG_LEVEL=INFO
    volumes:
      - ${MODEL_PATH}:/data/models/${MODEL_NAME}:ro
      - ${CACHE_DIR}:/data/cache
      - ${LOG_DIR}:/data/logs
    depends_on:
      - deepseek-master
    restart: unless-stopped
    
  deepseek-worker2:
    image: ${DOCKER_IMAGE}
    container_name: deepseek-worker2
    ports:
      - "8002:8000"
      - "9092:9090"
    environment:
      - NODE_TYPE=worker
      - NODE_ROLE=inference
      - CLUSTER_ENABLED=true
      - MASTER_NODE=deepseek-master:8000
      - MODEL_PATH=/data/models/${MODEL_NAME}
      - TENSOR_PARALLEL_SIZE=1
      - GPU_MEMORY_UTILIZATION=0.85
      - LOG_LEVEL=INFO
    volumes:
      - ${MODEL_PATH}:/data/models/${MODEL_NAME}:ro
      - ${CACHE_DIR}:/data/cache
      - ${LOG_DIR}:/data/logs
    depends_on:
      - deepseek-master
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    container_name: deepseek-nginx
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - deepseek-master
      - deepseek-worker1
      - deepseek-worker2
    restart: unless-stopped

networks:
  default:
    driver: bridge
EOF

    # 创建nginx配置
    cat > nginx.conf << EOF
events {
    worker_connections 1024;
}

http {
    upstream deepseek_backend {
        least_conn;
        server deepseek-master:8000 weight=3;
        server deepseek-worker1:8000 weight=2;
        server deepseek-worker2:8000 weight=1;
    }
    
    server {
        listen 80;
        server_name localhost;
        
        location / {
            proxy_pass http://deepseek_backend;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_timeout 300s;
            proxy_read_timeout 300s;
            proxy_send_timeout 300s;
        }
        
        location /health {
            access_log off;
            proxy_pass http://deepseek_backend/health;
        }
    }
}
EOF
    
    # 启动服务
    docker-compose up -d
    
    # 等待服务启动
    log_info "等待服务启动..."
    sleep 30
    
    # 检查服务状态
    docker-compose ps
    
    log_info "本地服务启动完成"
}

# 测试服务
test_service() {
    log_step "测试服务..."
    
    # 等待服务就绪
    log_info "等待服务就绪..."
    for i in {1..30}; do
        if curl -f http://localhost/health &> /dev/null; then
            break
        fi
        sleep 10
    done
    
    # 健康检查
    log_info "执行健康检查..."
    health_response=$(curl -s http://localhost/health)
    echo "健康检查响应: $health_response"
    
    # 测试API
    log_info "测试API..."
    cat > test_request.json << EOF
{
    "model": "deepseek-coder",
    "messages": [
        {
            "role": "user",
            "content": "请写一个Python函数来计算斐波那契数列"
        }
    ],
    "max_tokens": 200,
    "temperature": 0.7
}
EOF
    
    api_response=$(curl -s -X POST http://localhost/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d @test_request.json)
    
    echo "API测试响应: $api_response"
    
    # 清理测试文件
    rm -f test_request.json
    
    log_info "服务测试完成"
}

# 显示部署信息
show_deployment_info() {
    log_step "部署信息"
    
    echo -e "${GREEN}=== DeepSeek部署完成 ===${NC}"
    echo "模型路径: ${MODEL_PATH}"
    echo "缓存目录: ${CACHE_DIR}"
    echo "日志目录: ${LOG_DIR}"
    echo ""
    echo "服务端点:"
    echo "  - 主服务: http://localhost/"
    echo "  - 健康检查: http://localhost/health"
    echo "  - API文档: http://localhost/docs"
    echo "  - 指标监控: http://localhost:9090/metrics"
    echo ""
    echo "管理命令:"
    echo "  - 查看日志: docker-compose logs -f"
    echo "  - 重启服务: docker-compose restart"
    echo "  - 停止服务: docker-compose down"
    echo "  - 查看状态: docker-compose ps"
    echo ""
    echo "测试命令:"
    echo "  curl -X POST http://localhost/v1/chat/completions \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"model\":\"deepseek-coder\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}'"
}

# 主函数
main() {
    local deployment_type="local"
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --type)
                deployment_type="$2"
                shift 2
                ;;
            --model-path)
                MODEL_PATH="$2"
                shift 2
                ;;
            --skip-download)
                SKIP_DOWNLOAD=true
                shift
                ;;
            --help)
                echo "用法: $0 [选项]"
                echo "选项:"
                echo "  --type [local|k8s]     部署类型 (默认: local)"
                echo "  --model-path PATH      模型路径 (默认: /data/models/deepseek-coder-6.7b-instruct)"
                echo "  --skip-download        跳过模型下载"
                echo "  --help                 显示帮助信息"
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done
    
    log_info "开始部署DeepSeek模型..."
    log_info "部署类型: $deployment_type"
    log_info "模型路径: $MODEL_PATH"
    
    # 执行部署步骤
    check_dependencies
    create_directories
    
    if [ "$SKIP_DOWNLOAD" != "true" ]; then
        download_model
        verify_model
    fi
    
    build_docker_image
    
    if [ "$deployment_type" = "k8s" ]; then
        deploy_to_kubernetes
    else
        start_local_service
        test_service
    fi
    
    show_deployment_info
    
    log_info "DeepSeek模型部署完成！"
}

# 执行主函数
main "$@" 