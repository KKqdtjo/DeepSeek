#!/usr/bin/env python3
"""
DeepSeek分布式推理API服务
支持多节点模型分片推理和负载均衡
"""

import asyncio
import json
import time
import uuid
from typing import Dict, List, Optional, AsyncGenerator
from contextlib import asynccontextmanager

import torch
import uvicorn
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
import structlog
from prometheus_client import Counter, Histogram, Gauge, generate_latest
from transformers import AutoTokenizer
from vllm import AsyncLLMEngine, AsyncEngineArgs, SamplingParams
from vllm.utils import random_uuid

from config.settings import Settings
from utils.model_manager import ModelManager
from utils.cluster_manager import ClusterManager
from utils.metrics import MetricsCollector

# 配置日志
logger = structlog.get_logger()

# Prometheus指标
REQUEST_COUNT = Counter('deepseek_requests_total', 'Total requests', ['method', 'endpoint'])
REQUEST_DURATION = Histogram('deepseek_request_duration_seconds', 'Request duration')
ACTIVE_REQUESTS = Gauge('deepseek_active_requests', 'Active requests')
MODEL_LOAD_TIME = Histogram('deepseek_model_load_seconds', 'Model loading time')

# 全局变量
settings = Settings()
model_manager: Optional[ModelManager] = None
cluster_manager: Optional[ClusterManager] = None
metrics_collector: Optional[MetricsCollector] = None
llm_engine: Optional[AsyncLLMEngine] = None
tokenizer = None

# 请求和响应模型
class ChatMessage(BaseModel):
    role: str = Field(..., description="消息角色: user, assistant, system")
    content: str = Field(..., description="消息内容")

class ChatCompletionRequest(BaseModel):
    model: str = Field(default="deepseek-coder", description="模型名称")
    messages: List[ChatMessage] = Field(..., description="对话消息列表")
    temperature: float = Field(default=0.7, ge=0.0, le=2.0, description="采样温度")
    max_tokens: int = Field(default=2048, ge=1, le=4096, description="最大生成token数")
    top_p: float = Field(default=0.9, ge=0.0, le=1.0, description="核采样概率")
    stream: bool = Field(default=False, description="是否流式输出")
    stop: Optional[List[str]] = Field(default=None, description="停止词列表")

class ChatCompletionResponse(BaseModel):
    id: str = Field(..., description="响应ID")
    object: str = Field(default="chat.completion", description="对象类型")
    created: int = Field(..., description="创建时间戳")
    model: str = Field(..., description="使用的模型")
    choices: List[Dict] = Field(..., description="生成选择列表")
    usage: Dict = Field(..., description="token使用统计")

class HealthResponse(BaseModel):
    status: str = Field(..., description="服务状态")
    model_loaded: bool = Field(..., description="模型是否加载")
    cluster_status: str = Field(..., description="集群状态")
    node_id: str = Field(..., description="节点ID")
    uptime: float = Field(..., description="运行时间")

# 应用生命周期管理
@asynccontextmanager
async def lifespan(app: FastAPI):
    """应用启动和关闭时的处理"""
    global model_manager, cluster_manager, metrics_collector, llm_engine, tokenizer
    
    logger.info("启动DeepSeek API服务...")
    
    try:
        # 初始化组件
        model_manager = ModelManager(settings)
        cluster_manager = ClusterManager(settings)
        metrics_collector = MetricsCollector(settings)
        
        # 加载模型
        start_time = time.time()
        logger.info("开始加载DeepSeek模型...")
        
        # 配置vLLM引擎参数
        engine_args = AsyncEngineArgs(
            model=settings.model_path,
            tokenizer=settings.model_path,
            tensor_parallel_size=settings.tensor_parallel_size,
            dtype=settings.model_dtype,
            max_model_len=settings.max_model_len,
            gpu_memory_utilization=settings.gpu_memory_utilization,
            quantization=settings.quantization,
            trust_remote_code=True,
        )
        
        # 创建异步推理引擎
        llm_engine = AsyncLLMEngine.from_engine_args(engine_args)
        
        # 加载tokenizer
        tokenizer = AutoTokenizer.from_pretrained(
            settings.model_path,
            trust_remote_code=True
        )
        
        load_time = time.time() - start_time
        MODEL_LOAD_TIME.observe(load_time)
        
        logger.info(f"模型加载完成，耗时: {load_time:.2f}秒")
        
        # 注册到集群
        await cluster_manager.register_node()
        
        yield
        
    except Exception as e:
        logger.error(f"服务启动失败: {e}")
        raise
    finally:
        # 清理资源
        logger.info("关闭DeepSeek API服务...")
        if cluster_manager:
            await cluster_manager.unregister_node()

# 创建FastAPI应用
app = FastAPI(
    title="DeepSeek分布式推理API",
    description="基于vLLM的DeepSeek大语言模型分布式推理服务",
    version="1.0.0",
    lifespan=lifespan
)

# 添加CORS中间件
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.middleware("http")
async def metrics_middleware(request, call_next):
    """请求指标中间件"""
    start_time = time.time()
    ACTIVE_REQUESTS.inc()
    
    try:
        response = await call_next(request)
        REQUEST_COUNT.labels(
            method=request.method,
            endpoint=request.url.path
        ).inc()
        return response
    finally:
        REQUEST_DURATION.observe(time.time() - start_time)
        ACTIVE_REQUESTS.dec()

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """健康检查接口"""
    return HealthResponse(
        status="healthy" if llm_engine else "loading",
        model_loaded=llm_engine is not None,
        cluster_status=cluster_manager.get_status() if cluster_manager else "unknown",
        node_id=settings.node_id,
        uptime=time.time() - settings.start_time
    )

@app.get("/metrics")
async def get_metrics():
    """Prometheus指标接口"""
    return generate_latest()

@app.get("/models")
async def list_models():
    """列出可用模型"""
    return {
        "object": "list",
        "data": [
            {
                "id": "deepseek-coder",
                "object": "model",
                "created": int(time.time()),
                "owned_by": "deepseek"
            }
        ]
    }

def format_messages(messages: List[ChatMessage]) -> str:
    """格式化对话消息为模型输入"""
    formatted = ""
    for msg in messages:
        if msg.role == "system":
            formatted += f"System: {msg.content}\n"
        elif msg.role == "user":
            formatted += f"User: {msg.content}\n"
        elif msg.role == "assistant":
            formatted += f"Assistant: {msg.content}\n"
    
    formatted += "Assistant: "
    return formatted

@app.post("/v1/chat/completions")
async def create_chat_completion(request: ChatCompletionRequest):
    """创建聊天完成"""
    if not llm_engine:
        raise HTTPException(status_code=503, detail="模型尚未加载完成")
    
    try:
        # 格式化输入
        prompt = format_messages(request.messages)
        
        # 配置采样参数
        sampling_params = SamplingParams(
            temperature=request.temperature,
            top_p=request.top_p,
            max_tokens=request.max_tokens,
            stop=request.stop,
        )
        
        # 生成请求ID
        request_id = random_uuid()
        
        if request.stream:
            # 流式响应
            return StreamingResponse(
                stream_chat_completion(prompt, sampling_params, request_id, request.model),
                media_type="text/plain"
            )
        else:
            # 非流式响应
            return await generate_chat_completion(prompt, sampling_params, request_id, request.model)
            
    except Exception as e:
        logger.error(f"聊天完成请求失败: {e}")
        raise HTTPException(status_code=500, detail=str(e))

async def generate_chat_completion(prompt: str, sampling_params: SamplingParams, request_id: str, model: str) -> ChatCompletionResponse:
    """生成非流式聊天完成响应"""
    start_time = time.time()
    
    # 提交推理请求
    results_generator = llm_engine.generate(prompt, sampling_params, request_id)
    
    # 等待推理完成
    final_output = None
    async for request_output in results_generator:
        final_output = request_output
    
    if not final_output:
        raise HTTPException(status_code=500, detail="推理失败")
    
    # 构造响应
    output = final_output.outputs[0]
    generated_text = output.text
    
    # 计算token使用量
    prompt_tokens = len(tokenizer.encode(prompt))
    completion_tokens = len(tokenizer.encode(generated_text))
    
    return ChatCompletionResponse(
        id=request_id,
        created=int(start_time),
        model=model,
        choices=[
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": generated_text
                },
                "finish_reason": output.finish_reason
            }
        ],
        usage={
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": prompt_tokens + completion_tokens
        }
    )

async def stream_chat_completion(prompt: str, sampling_params: SamplingParams, request_id: str, model: str) -> AsyncGenerator[str, None]:
    """生成流式聊天完成响应"""
    start_time = time.time()
    
    # 提交推理请求
    results_generator = llm_engine.generate(prompt, sampling_params, request_id)
    
    # 流式输出
    async for request_output in results_generator:
        output = request_output.outputs[0]
        
        # 构造流式响应数据
        chunk = {
            "id": request_id,
            "object": "chat.completion.chunk",
            "created": int(start_time),
            "model": model,
            "choices": [
                {
                    "index": 0,
                    "delta": {
                        "content": output.text
                    },
                    "finish_reason": output.finish_reason
                }
            ]
        }
        
        yield f"data: {json.dumps(chunk, ensure_ascii=False)}\n\n"
    
    # 发送结束标记
    yield "data: [DONE]\n\n"

@app.post("/v1/completions")
async def create_completion(request: dict):
    """创建文本完成（兼容OpenAI API）"""
    if not llm_engine:
        raise HTTPException(status_code=503, detail="模型尚未加载完成")
    
    try:
        prompt = request.get("prompt", "")
        max_tokens = request.get("max_tokens", 100)
        temperature = request.get("temperature", 0.7)
        
        sampling_params = SamplingParams(
            temperature=temperature,
            max_tokens=max_tokens,
        )
        
        request_id = random_uuid()
        results_generator = llm_engine.generate(prompt, sampling_params, request_id)
        
        final_output = None
        async for request_output in results_generator:
            final_output = request_output
        
        if not final_output:
            raise HTTPException(status_code=500, detail="推理失败")
        
        output = final_output.outputs[0]
        
        return {
            "id": request_id,
            "object": "text_completion",
            "created": int(time.time()),
            "model": request.get("model", "deepseek-coder"),
            "choices": [
                {
                    "text": output.text,
                    "index": 0,
                    "finish_reason": output.finish_reason
                }
            ]
        }
        
    except Exception as e:
        logger.error(f"文本完成请求失败: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/cluster/status")
async def get_cluster_status():
    """获取集群状态"""
    if not cluster_manager:
        raise HTTPException(status_code=503, detail="集群管理器未初始化")
    
    return await cluster_manager.get_cluster_status()

@app.post("/cluster/rebalance")
async def rebalance_cluster(background_tasks: BackgroundTasks):
    """重新平衡集群负载"""
    if not cluster_manager:
        raise HTTPException(status_code=503, detail="集群管理器未初始化")
    
    background_tasks.add_task(cluster_manager.rebalance_load)
    return {"message": "集群重新平衡任务已启动"}

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host=settings.host,
        port=settings.port,
        workers=1,
        log_level=settings.log_level.lower(),
        access_log=True
    ) 