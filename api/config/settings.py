"""
DeepSeek分布式部署配置管理
"""

import os
import time
import uuid
from typing import Optional, List
from pydantic import BaseSettings, Field


class Settings(BaseSettings):
    """应用配置设置"""
    
    # 基础配置
    app_name: str = Field(default="deepseek-api", description="应用名称")
    version: str = Field(default="1.0.0", description="应用版本")
    debug: bool = Field(default=False, description="调试模式")
    log_level: str = Field(default="INFO", description="日志级别")
    
    # 服务配置
    host: str = Field(default="0.0.0.0", description="服务监听地址")
    port: int = Field(default=8000, description="服务端口")
    workers: int = Field(default=1, description="工作进程数")
    
    # 节点配置
    node_id: str = Field(default_factory=lambda: str(uuid.uuid4()), description="节点ID")
    node_type: str = Field(default="worker", description="节点类型")
    node_role: str = Field(default="inference", description="节点角色")
    start_time: float = Field(default_factory=time.time, description="启动时间")
    
    # 模型配置
    model_name: str = Field(default="deepseek-coder", description="模型名称")
    model_path: str = Field(default="/data/models/deepseek-coder-6.7b-instruct", description="模型路径")
    model_dtype: str = Field(default="auto", description="模型数据类型")
    max_model_len: int = Field(default=4096, description="最大模型长度")
    
    # vLLM配置
    tensor_parallel_size: int = Field(default=1, description="张量并行大小")
    pipeline_parallel_size: int = Field(default=1, description="流水线并行大小")
    gpu_memory_utilization: float = Field(default=0.85, description="GPU内存利用率")
    quantization: Optional[str] = Field(default=None, description="量化方法")
    max_num_seqs: int = Field(default=256, description="最大并发序列数")
    max_num_batched_tokens: int = Field(default=8192, description="最大批处理token数")
    
    # 推理配置
    default_temperature: float = Field(default=0.7, description="默认采样温度")
    default_top_p: float = Field(default=0.9, description="默认top-p值")
    default_max_tokens: int = Field(default=2048, description="默认最大生成token数")
    default_stop_sequences: List[str] = Field(default_factory=list, description="默认停止序列")
    
    # 集群配置
    cluster_enabled: bool = Field(default=True, description="是否启用集群模式")
    master_node: Optional[str] = Field(default=None, description="主节点地址")
    cluster_discovery_method: str = Field(default="kubernetes", description="集群发现方法")
    heartbeat_interval: int = Field(default=30, description="心跳间隔(秒)")
    
    # Kubernetes配置
    k8s_namespace: str = Field(default="default", description="K8s命名空间")
    k8s_service_name: str = Field(default="deepseek-service", description="K8s服务名")
    k8s_pod_name: str = Field(default_factory=lambda: os.getenv("HOSTNAME", "unknown"), description="Pod名称")
    
    # 华为云配置
    hw_access_key: Optional[str] = Field(default=None, description="华为云访问密钥")
    hw_secret_key: Optional[str] = Field(default=None, description="华为云私有密钥")
    hw_region: str = Field(default="cn-north-4", description="华为云区域")
    obs_bucket: str = Field(default="deepseek-models", description="OBS存储桶")
    obs_endpoint: str = Field(default="obs.cn-north-4.myhuaweicloud.com", description="OBS端点")
    
    # 存储配置
    model_cache_dir: str = Field(default="/data/cache", description="模型缓存目录")
    log_dir: str = Field(default="/data/logs", description="日志目录")
    temp_dir: str = Field(default="/tmp", description="临时目录")
    
    # 监控配置
    metrics_enabled: bool = Field(default=True, description="是否启用指标收集")
    metrics_port: int = Field(default=9090, description="指标端口")
    jaeger_enabled: bool = Field(default=False, description="是否启用Jaeger追踪")
    jaeger_endpoint: Optional[str] = Field(default=None, description="Jaeger端点")
    
    # 安全配置
    api_key: Optional[str] = Field(default=None, description="API密钥")
    jwt_secret: Optional[str] = Field(default=None, description="JWT密钥")
    cors_origins: List[str] = Field(default=["*"], description="CORS允许源")
    rate_limit_enabled: bool = Field(default=True, description="是否启用限流")
    rate_limit_requests: int = Field(default=100, description="限流请求数")
    rate_limit_window: int = Field(default=60, description="限流时间窗口")
    
    # 性能配置
    max_concurrent_requests: int = Field(default=100, description="最大并发请求数")
    request_timeout: int = Field(default=300, description="请求超时时间")
    keep_alive_timeout: int = Field(default=5, description="Keep-Alive超时")
    
    # 健康检查配置
    health_check_enabled: bool = Field(default=True, description="是否启用健康检查")
    health_check_interval: int = Field(default=30, description="健康检查间隔")
    health_check_timeout: int = Field(default=10, description="健康检查超时")
    
    # 负载均衡配置
    load_balance_strategy: str = Field(default="round_robin", description="负载均衡策略")
    sticky_sessions: bool = Field(default=False, description="是否启用会话粘性")
    circuit_breaker_enabled: bool = Field(default=True, description="是否启用熔断器")
    circuit_breaker_threshold: int = Field(default=5, description="熔断器阈值")
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False
        
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._setup_directories()
        self._validate_config()
    
    def _setup_directories(self):
        """创建必要的目录"""
        import os
        os.makedirs(self.model_cache_dir, exist_ok=True)
        os.makedirs(self.log_dir, exist_ok=True)
        os.makedirs(os.path.dirname(self.model_path), exist_ok=True)
    
    def _validate_config(self):
        """验证配置"""
        if self.cluster_enabled and not self.master_node and self.node_type == "worker":
            raise ValueError("集群模式下工作节点必须指定主节点地址")
        
        if self.tensor_parallel_size < 1:
            raise ValueError("张量并行大小必须大于0")
        
        if self.gpu_memory_utilization <= 0 or self.gpu_memory_utilization > 1:
            raise ValueError("GPU内存利用率必须在0-1之间")
    
    @property
    def is_master_node(self) -> bool:
        """是否为主节点"""
        return self.node_type == "master"
    
    @property
    def is_worker_node(self) -> bool:
        """是否为工作节点"""
        return self.node_type == "worker"
    
    @property
    def model_config_path(self) -> str:
        """模型配置路径"""
        return os.path.join(self.model_path, "config.json")
    
    @property
    def tokenizer_path(self) -> str:
        """分词器路径"""
        return self.model_path
    
    def get_obs_config(self) -> dict:
        """获取OBS配置"""
        return {
            "access_key_id": self.hw_access_key,
            "secret_access_key": self.hw_secret_key,
            "server": self.obs_endpoint,
            "signature": "v4"
        }
    
    def get_k8s_labels(self) -> dict:
        """获取K8s标签"""
        return {
            "app": self.app_name,
            "version": self.version,
            "node-type": self.node_type,
            "node-role": self.node_role,
            "node-id": self.node_id
        }
    
    def get_prometheus_labels(self) -> dict:
        """获取Prometheus标签"""
        return {
            "instance": f"{self.host}:{self.port}",
            "node_id": self.node_id,
            "node_type": self.node_type,
            "model": self.model_name
        }


# 全局配置实例
settings = Settings()


# 环境特定配置
class DevelopmentSettings(Settings):
    """开发环境配置"""
    debug: bool = True
    log_level: str = "DEBUG"
    workers: int = 1


class ProductionSettings(Settings):
    """生产环境配置"""
    debug: bool = False
    log_level: str = "INFO"
    workers: int = 4


class TestingSettings(Settings):
    """测试环境配置"""
    debug: bool = True
    log_level: str = "DEBUG"
    model_path: str = "/tmp/test-model"


def get_settings() -> Settings:
    """根据环境获取配置"""
    env = os.getenv("ENVIRONMENT", "development").lower()
    
    if env == "production":
        return ProductionSettings()
    elif env == "testing":
        return TestingSettings()
    else:
        return DevelopmentSettings() 