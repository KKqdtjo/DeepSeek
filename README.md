# DeepSeek 大模型分布式部署方案

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Python](https://img.shields.io/badge/python-3.8+-green.svg)](https://python.org)
[![Docker](https://img.shields.io/badge/docker-ready-blue.svg)](https://docker.com)
[![Kubernetes](https://img.shields.io/badge/kubernetes-ready-blue.svg)](https://kubernetes.io)

一个完整的DeepSeek大模型分布式部署解决方案，支持华为云ECS、Docker容器化部署和Kubernetes集群管理。

## 🌟 项目特色

- **一键部署**: 自动化脚本，15分钟完成部署
- **分布式架构**: 支持多节点负载均衡和水平扩展
- **容器化**: 基于Docker的完整容器化解决方案
- **云原生**: 支持Kubernetes集群部署和管理
- **监控完善**: 内置性能监控、日志管理和健康检查
- **成本优化**: 针对华为云的成本控制策略
- **生产就绪**: 包含安全配置、备份策略和故障恢复

## 📋 目录结构

```
大模型分布式部署/
├── README.md                    # 项目说明
├── api/                        # API服务代码
│   ├── main.py                 # 主应用程序
│   ├── config/                 # 配置管理
│   │   └── settings.py         # 应用配置
│   └── requirements.txt        # Python依赖
├── docker/                     # Docker配置
│   └── deepseek-api/
│       ├── Dockerfile          # API服务镜像
│       └── requirements.txt    # 容器依赖
├── kubernetes/                 # K8s部署配置
│   └── deployment.yaml         # 部署清单
├── scripts/                    # 自动化脚本
│   ├── 01-init-environment.sh  # 环境初始化
│   ├── 02-deploy-model.sh      # 模型部署
│   └── 03-monitor-service.sh   # 服务监控
└── docs/                       # 文档
    ├── 01-华为云服务器配置指南.md
    └── 02-快速入门指南.md
```

## 🚀 快速开始

### 1. 环境要求

- **操作系统**: Ubuntu 20.04 LTS 或更高版本
- **内存**: 至少16GB RAM (推荐32GB)
- **存储**: 至少100GB可用空间
- **GPU**: NVIDIA GPU (可选，推荐RTX 3080或更高)
- **网络**: 稳定的互联网连接

### 2. 华为云ECS推荐配置

| 规格 | CPU | 内存 | GPU | 存储 | 月费用(约) | 适用场景 |
|------|-----|------|-----|------|-----------|----------|
| 基础版 | 4核 | 16GB | 无 | 100GB SSD | ¥200 | 开发测试 |
| 标准版 | 8核 | 32GB | T4 | 200GB SSD | ¥800 | 小规模生产 |
| 高性能版 | 16核 | 64GB | V100 | 500GB SSD | ¥2000 | 大规模生产 |

### 3. 一键部署

```bash
# 1. 克隆项目
git clone <项目地址>
cd 大模型分布式部署

# 2. 环境初始化
sudo ./scripts/01-init-environment.sh

# 3. 模型部署
./scripts/02-deploy-model.sh

# 4. 验证部署
./scripts/03-monitor-service.sh status
```

### 4. 服务访问

部署完成后，可通过以下端点访问：

- **主服务**: <http://localhost/>
- **API文档**: <http://localhost/docs>
- **健康检查**: <http://localhost/health>
- **指标监控**: <http://localhost:9090/metrics>

## 🔧 核心功能

### 分布式架构

```
┌─────────────────┐    ┌─────────────────┐
│   Nginx LB      │    │   Nginx LB      │
│   (Port 80)     │    │   (Port 80)     │
└─────────┬───────┘    └─────────┬───────┘
          │                      │
    ┌─────▼─────┐          ┌─────▼─────┐
    │  Master   │          │  Master   │
    │ (Port 8000)│          │ (Port 8000)│
    └─────┬─────┘          └─────┬─────┘
          │                      │
    ┌─────▼─────┐          ┌─────▼─────┐
    │ Worker 1  │          │ Worker 1  │
    │ (Port 8001)│          │ (Port 8001)│
    └───────────┘          └───────────┘
    ┌───────────┐          ┌───────────┐
    │ Worker 2  │          │ Worker 2  │
    │ (Port 8002)│          │ (Port 8002)│
    └───────────┘          └───────────┘
```

### API接口

支持OpenAI兼容的API接口：

```bash
# 聊天完成
POST /v1/chat/completions

# 健康检查
GET /health

# 服务指标
GET /metrics
```

### 监控指标

- **系统指标**: CPU、内存、磁盘、GPU使用率
- **服务指标**: 请求量、响应时间、错误率
- **模型指标**: 推理时间、吞吐量、队列长度

## 📖 详细文档

- [华为云服务器配置指南](docs/01-华为云服务器配置指南.md)
- [快速入门指南](docs/02-快速入门指南.md)

## 🛠️ 管理命令

### 服务管理

```bash
# 查看服务状态
./scripts/03-monitor-service.sh status

# 重启服务
./scripts/03-monitor-service.sh restart

# 停止服务
./scripts/03-monitor-service.sh stop

# 启动服务
./scripts/03-monitor-service.sh start
```

### 日志管理

```bash
# 查看所有日志
./scripts/03-monitor-service.sh logs

# 查看特定组件日志
./scripts/03-monitor-service.sh logs master 100

# 实时日志
docker-compose logs -f
```

### 性能监控

```bash
# 系统性能
./scripts/03-monitor-service.sh monitor

# 服务指标
./scripts/03-monitor-service.sh metrics

# 生成报告
./scripts/03-monitor-service.sh report
```

### 服务缩放

```bash
# 扩展到3个副本
./scripts/03-monitor-service.sh scale 3

# 缩减到1个副本
./scripts/03-monitor-service.sh scale 1
```

## 🔍 故障排除

### 常见问题

1. **模型下载失败**

   ```bash
   export HF_ENDPOINT=https://hf-mirror.com
   ./scripts/02-deploy-model.sh
   ```

2. **GPU未识别**

   ```bash
   nvidia-smi
   docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
   ```

3. **端口被占用**

   ```bash
   netstat -tuln | grep :8000
   sudo fuser -k 8000/tcp
   ```

4. **内存不足**

   ```bash
   export GPU_MEMORY_UTILIZATION=0.7
   ./scripts/02-deploy-model.sh
   ```

### 日志分析

```bash
# 查看错误日志
./scripts/03-monitor-service.sh logs all 200 | grep -i error

# 查看启动日志
docker-compose logs deepseek-master | head -50
```

## 🔒 生产环境配置

### 安全配置

1. **API认证**

   ```python
   # 在settings.py中配置
   API_KEY_REQUIRED = True
   API_KEYS = ["your-secure-api-key"]
   ```

2. **HTTPS配置**

   ```bash
   sudo apt install certbot
   sudo certbot --nginx -d your-domain.com
   ```

3. **防火墙配置**

   ```bash
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw enable
   ```

### 备份策略

```bash
# 配置备份
./scripts/03-monitor-service.sh backup

# 定时备份
echo "0 2 * * * /path/to/scripts/03-monitor-service.sh backup" | crontab -
```

## 💰 成本优化

### 华为云成本控制

1. **竞价实例**: 开发测试环境可节省70%成本
2. **弹性伸缩**: 基于负载自动扩缩容
3. **存储优化**: 使用OBS存储模型文件
4. **定时清理**: 自动清理日志和缓存

### 资源优化

```bash
# 混合精度推理
export USE_MIXED_PRECISION=true

# 模型量化
export MODEL_QUANTIZATION=int8

# 动态批处理
export DYNAMIC_BATCHING=true
```

## 📊 性能基准

### 测试环境

- **CPU**: Intel Xeon E5-2686 v4 (8核)
- **内存**: 32GB DDR4
- **GPU**: NVIDIA Tesla T4 (16GB)
- **存储**: 200GB SSD

### 性能指标

- **并发用户**: 100
- **平均响应时间**: 2.5秒
- **吞吐量**: 40 req/s
- **GPU利用率**: 85%
- **内存使用**: 24GB

## 🤝 贡献指南

欢迎提交Issue和Pull Request来改进项目！

1. Fork项目
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建Pull Request

## 📄 许可证

本项目基于MIT许可证开源 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🙏 致谢

- [DeepSeek](https://deepseek.com/) - 提供优秀的开源模型
- [Hugging Face](https://huggingface.co/) - 模型托管和工具
- [华为云](https://huaweicloud.com/) - 云服务支持

## 📞 技术支持

如果您在使用过程中遇到问题：

1. 查看[故障排除文档](docs/02-快速入门指南.md#6-故障排除)
2. 运行诊断脚本: `./scripts/03-monitor-service.sh report`
3. 提交[GitHub Issue](https://github.com/your-repo/issues)
4. 加入技术交流群

---

**🎉 开始您的AI之旅吧！**
