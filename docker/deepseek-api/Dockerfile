# DeepSeek API服务容器镜像
FROM nvidia/cuda:11.8-devel-ubuntu20.04

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV CUDA_VISIBLE_DEVICES=0

# 设置工作目录
WORKDIR /app

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    python3.9 \
    python3.9-dev \
    python3-pip \
    git \
    wget \
    curl \
    vim \
    htop \
    && rm -rf /var/lib/apt/lists/*

# 创建软链接
RUN ln -sf /usr/bin/python3.9 /usr/bin/python

# 升级pip
RUN python -m pip install --upgrade pip

# 安装PyTorch (CUDA版本)
RUN pip install torch==2.0.1+cu118 torchvision==0.15.2+cu118 torchaudio==2.0.2 \
    --index-url https://download.pytorch.org/whl/cu118

# 安装Transformers和相关依赖
RUN pip install \
    transformers==4.35.0 \
    accelerate==0.24.0 \
    bitsandbytes==0.41.1 \
    sentencepiece==0.1.99 \
    protobuf==3.20.3 \
    safetensors==0.4.0

# 安装vLLM推理框架
RUN pip install vllm==0.2.2

# 安装Web服务依赖
RUN pip install \
    fastapi==0.104.1 \
    uvicorn==0.24.0 \
    pydantic==2.5.0 \
    sse-starlette==1.6.5 \
    httpx==0.25.2

# 安装监控和日志依赖
RUN pip install \
    prometheus-client==0.19.0 \
    structlog==23.2.0 \
    colorama==0.4.6

# 复制应用代码
COPY src/ /app/src/
COPY config/ /app/config/
COPY requirements.txt /app/

# 安装应用依赖
RUN pip install -r requirements.txt

# 创建模型目录
RUN mkdir -p /app/models /app/logs /app/cache

# 设置权限
RUN chmod +x /app/src/start.sh

# 暴露端口
EXPOSE 8000

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# 启动命令
CMD ["/app/src/start.sh"] 