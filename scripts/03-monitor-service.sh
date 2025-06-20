#!/bin/bash

# DeepSeek服务监控和管理脚本
# 用于监控、管理和维护DeepSeek模型服务

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置变量
SERVICE_NAME="deepseek"
NAMESPACE="default"
LOG_DIR="/data/logs"
METRICS_PORT="9090"
API_PORT="8000"
HEALTH_ENDPOINT="http://localhost/health"
METRICS_ENDPOINT="http://localhost:${METRICS_PORT}/metrics"

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

log_success() {
    echo -e "${PURPLE}[SUCCESS]${NC} $1"
}

# 检查服务状态
check_service_status() {
    log_step "检查服务状态..."
    
    # 检查Docker服务
    if command -v docker-compose &> /dev/null; then
        echo -e "${CYAN}=== Docker Compose 服务状态 ===${NC}"
        docker-compose ps 2>/dev/null || log_warn "Docker Compose服务未运行"
        echo ""
    fi
    
    # 检查Kubernetes服务
    if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
        echo -e "${CYAN}=== Kubernetes 服务状态 ===${NC}"
        kubectl get pods -n ${NAMESPACE} -l app=deepseek 2>/dev/null || log_warn "Kubernetes服务未运行"
        kubectl get services -n ${NAMESPACE} -l app=deepseek 2>/dev/null || true
        echo ""
    fi
    
    # 检查端口占用
    echo -e "${CYAN}=== 端口状态 ===${NC}"
    check_port_status 80 "负载均衡器"
    check_port_status 8000 "主服务"
    check_port_status 8001 "工作节点1"
    check_port_status 8002 "工作节点2"
    check_port_status 9090 "指标监控"
    echo ""
}

# 检查端口状态
check_port_status() {
    local port=$1
    local service_name=$2
    
    if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
        echo -e "${GREEN}✓${NC} 端口 ${port} (${service_name}) - 正在运行"
    else
        echo -e "${RED}✗${NC} 端口 ${port} (${service_name}) - 未运行"
    fi
}

# 健康检查
health_check() {
    log_step "执行健康检查..."
    
    # API健康检查
    if curl -f -s ${HEALTH_ENDPOINT} > /dev/null 2>&1; then
        local health_response=$(curl -s ${HEALTH_ENDPOINT})
        log_success "API健康检查通过"
        echo "响应: $health_response"
    else
        log_error "API健康检查失败"
        return 1
    fi
    
    # 检查各个组件
    check_component_health "master" "8000"
    check_component_health "worker1" "8001"
    check_component_health "worker2" "8002"
    
    echo ""
}

# 检查组件健康状态
check_component_health() {
    local component=$1
    local port=$2
    
    if curl -f -s "http://localhost:${port}/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} ${component} 组件健康"
    else
        echo -e "${RED}✗${NC} ${component} 组件异常"
    fi
}

# 性能监控
performance_monitor() {
    log_step "性能监控..."
    
    echo -e "${CYAN}=== 系统资源使用情况 ===${NC}"
    
    # CPU使用率
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    echo "CPU使用率: ${cpu_usage}%"
    
    # 内存使用率
    memory_info=$(free -h | grep "Mem:")
    echo "内存使用: $memory_info"
    
    # 磁盘使用率
    echo "磁盘使用:"
    df -h | grep -E "/$|/data"
    
    # GPU使用率（如果有）
    if command -v nvidia-smi &> /dev/null; then
        echo -e "\n${CYAN}=== GPU使用情况 ===${NC}"
        nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits
    fi
    
    echo ""
    
    # Docker容器资源使用
    if command -v docker &> /dev/null; then
        echo -e "${CYAN}=== Docker容器资源使用 ===${NC}"
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null || log_warn "无法获取Docker统计信息"
        echo ""
    fi
}

# 获取指标数据
get_metrics() {
    log_step "获取服务指标..."
    
    if curl -f -s ${METRICS_ENDPOINT} > /dev/null 2>&1; then
        local metrics=$(curl -s ${METRICS_ENDPOINT})
        
        echo -e "${CYAN}=== 服务指标 ===${NC}"
        
        # 提取关键指标
        echo "请求总数:"
        echo "$metrics" | grep "^http_requests_total" | head -5
        
        echo -e "\n请求延迟:"
        echo "$metrics" | grep "^http_request_duration" | head -5
        
        echo -e "\n模型推理指标:"
        echo "$metrics" | grep "^model_inference" | head -5
        
        echo -e "\n内存使用:"
        echo "$metrics" | grep "^process_resident_memory_bytes"
        
    else
        log_warn "无法获取指标数据"
    fi
    
    echo ""
}

# 查看日志
view_logs() {
    local component=${1:-"all"}
    local lines=${2:-50}
    
    log_step "查看日志 (组件: $component, 行数: $lines)..."
    
    case $component in
        "all")
            if command -v docker-compose &> /dev/null; then
                docker-compose logs --tail=$lines
            else
                view_file_logs $lines
            fi
            ;;
        "master"|"worker1"|"worker2"|"nginx")
            if command -v docker-compose &> /dev/null; then
                docker-compose logs --tail=$lines deepseek-$component
            else
                log_error "Docker Compose未运行"
            fi
            ;;
        "k8s")
            if command -v kubectl &> /dev/null; then
                kubectl logs -n ${NAMESPACE} -l app=deepseek --tail=$lines
            else
                log_error "kubectl未配置"
            fi
            ;;
        *)
            log_error "未知组件: $component"
            echo "可用组件: all, master, worker1, worker2, nginx, k8s"
            ;;
    esac
}

# 查看文件日志
view_file_logs() {
    local lines=$1
    
    if [ -d "$LOG_DIR" ]; then
        echo -e "${CYAN}=== 应用日志 ===${NC}"
        find $LOG_DIR -name "*.log" -type f | while read logfile; do
            echo -e "\n${YELLOW}--- $(basename $logfile) ---${NC}"
            tail -n $lines "$logfile" 2>/dev/null || log_warn "无法读取 $logfile"
        done
    else
        log_warn "日志目录不存在: $LOG_DIR"
    fi
}

# 重启服务
restart_service() {
    local component=${1:-"all"}
    
    log_step "重启服务 (组件: $component)..."
    
    case $component in
        "all")
            if command -v docker-compose &> /dev/null; then
                docker-compose restart
                log_success "所有服务已重启"
            else
                log_error "Docker Compose未运行"
            fi
            ;;
        "master"|"worker1"|"worker2"|"nginx")
            if command -v docker-compose &> /dev/null; then
                docker-compose restart deepseek-$component
                log_success "${component} 服务已重启"
            else
                log_error "Docker Compose未运行"
            fi
            ;;
        "k8s")
            if command -v kubectl &> /dev/null; then
                kubectl rollout restart deployment/deepseek-master -n ${NAMESPACE}
                kubectl rollout restart deployment/deepseek-worker -n ${NAMESPACE}
                log_success "Kubernetes服务已重启"
            else
                log_error "kubectl未配置"
            fi
            ;;
        *)
            log_error "未知组件: $component"
            echo "可用组件: all, master, worker1, worker2, nginx, k8s"
            ;;
    esac
}

# 停止服务
stop_service() {
    local component=${1:-"all"}
    
    log_step "停止服务 (组件: $component)..."
    
    case $component in
        "all")
            if command -v docker-compose &> /dev/null; then
                docker-compose down
                log_success "所有服务已停止"
            else
                log_error "Docker Compose未运行"
            fi
            ;;
        "master"|"worker1"|"worker2"|"nginx")
            if command -v docker-compose &> /dev/null; then
                docker-compose stop deepseek-$component
                log_success "${component} 服务已停止"
            else
                log_error "Docker Compose未运行"
            fi
            ;;
        "k8s")
            if command -v kubectl &> /dev/null; then
                kubectl delete -f kubernetes/deployment.yaml
                log_success "Kubernetes服务已停止"
            else
                log_error "kubectl未配置"
            fi
            ;;
        *)
            log_error "未知组件: $component"
            echo "可用组件: all, master, worker1, worker2, nginx, k8s"
            ;;
    esac
}

# 启动服务
start_service() {
    local component=${1:-"all"}
    
    log_step "启动服务 (组件: $component)..."
    
    case $component in
        "all")
            if [ -f "docker-compose.yml" ]; then
                docker-compose up -d
                log_success "所有服务已启动"
            else
                log_error "docker-compose.yml文件不存在"
            fi
            ;;
        "master"|"worker1"|"worker2"|"nginx")
            if [ -f "docker-compose.yml" ]; then
                docker-compose up -d deepseek-$component
                log_success "${component} 服务已启动"
            else
                log_error "docker-compose.yml文件不存在"
            fi
            ;;
        "k8s")
            if [ -f "kubernetes/deployment.yaml" ]; then
                kubectl apply -f kubernetes/deployment.yaml
                log_success "Kubernetes服务已启动"
            else
                log_error "kubernetes/deployment.yaml文件不存在"
            fi
            ;;
        *)
            log_error "未知组件: $component"
            echo "可用组件: all, master, worker1, worker2, nginx, k8s"
            ;;
    esac
}

# 缩放服务
scale_service() {
    local replicas=$1
    
    if [ -z "$replicas" ]; then
        log_error "请指定副本数量"
        return 1
    fi
    
    log_step "缩放服务到 $replicas 个副本..."
    
    if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
        kubectl scale deployment/deepseek-worker --replicas=$replicas -n ${NAMESPACE}
        log_success "服务已缩放到 $replicas 个副本"
    else
        log_warn "Kubernetes未配置，尝试使用Docker Compose缩放..."
        if command -v docker-compose &> /dev/null; then
            docker-compose up -d --scale deepseek-worker1=$replicas
            log_success "Docker服务已缩放"
        else
            log_error "无法缩放服务"
        fi
    fi
}

# 测试API
test_api() {
    log_step "测试API..."
    
    # 创建测试请求
    cat > /tmp/test_request.json << EOF
{
    "model": "deepseek-coder",
    "messages": [
        {
            "role": "user",
            "content": "写一个简单的Hello World程序"
        }
    ],
    "max_tokens": 100,
    "temperature": 0.7
}
EOF
    
    # 发送请求
    local start_time=$(date +%s.%N)
    local response=$(curl -s -X POST http://localhost/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d @/tmp/test_request.json)
    local end_time=$(date +%s.%N)
    
    # 计算响应时间
    local duration=$(echo "$end_time - $start_time" | bc)
    
    echo -e "${CYAN}=== API测试结果 ===${NC}"
    echo "响应时间: ${duration}秒"
    echo "响应内容:"
    echo "$response" | python -m json.tool 2>/dev/null || echo "$response"
    
    # 清理测试文件
    rm -f /tmp/test_request.json
    
    echo ""
}

# 备份配置
backup_config() {
    local backup_dir="/data/backup/$(date +%Y%m%d_%H%M%S)"
    
    log_step "备份配置到 $backup_dir..."
    
    mkdir -p $backup_dir
    
    # 备份Docker配置
    if [ -f "docker-compose.yml" ]; then
        cp docker-compose.yml $backup_dir/
    fi
    
    if [ -f "nginx.conf" ]; then
        cp nginx.conf $backup_dir/
    fi
    
    # 备份Kubernetes配置
    if [ -d "kubernetes" ]; then
        cp -r kubernetes $backup_dir/
    fi
    
    # 备份应用配置
    if [ -d "api/config" ]; then
        cp -r api/config $backup_dir/
    fi
    
    log_success "配置已备份到 $backup_dir"
}

# 清理资源
cleanup() {
    log_step "清理资源..."
    
    # 清理Docker资源
    if command -v docker &> /dev/null; then
        echo "清理未使用的Docker镜像..."
        docker image prune -f
        
        echo "清理未使用的Docker容器..."
        docker container prune -f
        
        echo "清理未使用的Docker网络..."
        docker network prune -f
        
        echo "清理未使用的Docker卷..."
        docker volume prune -f
    fi
    
    # 清理日志文件
    if [ -d "$LOG_DIR" ]; then
        echo "清理旧日志文件..."
        find $LOG_DIR -name "*.log" -mtime +7 -delete
    fi
    
    # 清理缓存文件
    if [ -d "/data/cache" ]; then
        echo "清理缓存文件..."
        find /data/cache -name "*.tmp" -delete
    fi
    
    log_success "资源清理完成"
}

# 生成报告
generate_report() {
    local report_file="/tmp/deepseek_report_$(date +%Y%m%d_%H%M%S).txt"
    
    log_step "生成系统报告..."
    
    {
        echo "DeepSeek服务状态报告"
        echo "生成时间: $(date)"
        echo "========================================"
        echo ""
        
        echo "1. 服务状态"
        echo "--------"
        check_service_status
        echo ""
        
        echo "2. 系统资源"
        echo "--------"
        performance_monitor
        echo ""
        
        echo "3. 健康检查"
        echo "--------"
        health_check
        echo ""
        
        echo "4. 最近日志"
        echo "--------"
        view_logs all 20
        
    } > $report_file
    
    log_success "报告已生成: $report_file"
    echo "查看报告: cat $report_file"
}

# 显示帮助信息
show_help() {
    echo -e "${CYAN}DeepSeek服务监控和管理工具${NC}"
    echo ""
    echo "用法: $0 <命令> [参数]"
    echo ""
    echo "命令:"
    echo "  status              - 检查服务状态"
    echo "  health              - 执行健康检查"
    echo "  monitor             - 性能监控"
    echo "  metrics             - 获取服务指标"
    echo "  logs [组件] [行数]   - 查看日志"
    echo "  restart [组件]      - 重启服务"
    echo "  stop [组件]         - 停止服务"
    echo "  start [组件]        - 启动服务"
    echo "  scale <副本数>      - 缩放服务"
    echo "  test                - 测试API"
    echo "  backup              - 备份配置"
    echo "  cleanup             - 清理资源"
    echo "  report              - 生成状态报告"
    echo "  help                - 显示帮助信息"
    echo ""
    echo "组件选项:"
    echo "  all                 - 所有组件 (默认)"
    echo "  master              - 主节点"
    echo "  worker1             - 工作节点1"
    echo "  worker2             - 工作节点2"
    echo "  nginx               - 负载均衡器"
    echo "  k8s                 - Kubernetes部署"
    echo ""
    echo "示例:"
    echo "  $0 status           # 检查所有服务状态"
    echo "  $0 logs master 100  # 查看主节点最近100行日志"
    echo "  $0 restart worker1  # 重启工作节点1"
    echo "  $0 scale 3          # 缩放到3个副本"
}

# 主函数
main() {
    case ${1:-"help"} in
        "status")
            check_service_status
            ;;
        "health")
            health_check
            ;;
        "monitor")
            performance_monitor
            ;;
        "metrics")
            get_metrics
            ;;
        "logs")
            view_logs $2 $3
            ;;
        "restart")
            restart_service $2
            ;;
        "stop")
            stop_service $2
            ;;
        "start")
            start_service $2
            ;;
        "scale")
            scale_service $2
            ;;
        "test")
            test_api
            ;;
        "backup")
            backup_config
            ;;
        "cleanup")
            cleanup
            ;;
        "report")
            generate_report
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            log_error "未知命令: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@" 