# GPUStack + Qwen3-VL 故障排查指南

## 问题现象
运行 inference-benchmarker 时出现 `index out of bounds: the len is 0 but the index is 0` 错误。

## 根本原因
API 返回的响应中 `choices` 数组为空，这通常是因为：

1. **模型名称不匹配** - GPUStack 中的模型名称与命令中的不一致
2. **Qwen3-VL 是多模态模型** - 可能需要特殊的消息格式
3. **API 配置问题** - max_tokens、temperature 等参数不兼容
4. **vLLM 版本兼容性** - 某些版本对 VL 模型的支持不完整

## 诊断步骤

### 步骤 1：运行诊断脚本
```bash
cd /home/user/inference-benchmarker
./debug_api.sh
```

这个脚本会：
- 检查 API 是否可访问
- 列出所有可用的模型
- 测试非流式和流式请求
- 测试不同的消息格式

### 步骤 2：检查模型名称

在诊断脚本的 "Test 2" 输出中，找到实际的模型名称。常见情况：

```bash
# GPUStack 可能返回的模型名称：
- qwen3-vl-8b-instruct
- Qwen/Qwen3-VL-8B-Instruct
- qwen3-vl
- 或其他变体
```

**解决方案**：使用实际返回的模型名称

### 步骤 3：检查 API 响应格式

#### 情况 A：choices 数组在非流式请求中正常
如果 Test 3 中 choices 不为空，但流式请求失败，可能是流式 API 的问题。

**解决方案**：检查 vLLM 版本，或考虑使用非流式模式

#### 情况 B：所有请求的 choices 都为空
这表明 API 配置或模型不兼容。

**可能的原因**：
1. Qwen3-VL 需要特殊的消息格式（参见下文）
2. GPUStack/vLLM 版本太旧
3. 模型没有正确加载

### 步骤 4：测试不同的消息格式

Qwen3-VL 作为视觉语言模型，可能需要特殊格式：

#### 标准格式（当前使用）:
```json
{
  "messages": [
    {"role": "user", "content": "Hello"}
  ]
}
```

#### 多模态格式（可能需要）:
```json
{
  "messages": [
    {
      "role": "user",
      "content": [
        {"type": "text", "text": "Hello"}
      ]
    }
  ]
}
```

## 常见解决方案

### 解决方案 1：使用正确的模型名称

```bash
# 首先运行诊断脚本找到正确的模型名称
./debug_api.sh

# 然后使用实际的模型名称
inference-benchmarker \
  --tokenizer-name Qwen/Qwen3-VL-8B-Instruct \
  --model-name <实际的模型名称> \
  --url http://localhost:8001 \
  --api-key gpustack_d521a91e37db5823_542fb6d87249361f5133216132800e4e \
  --benchmark-kind sweep \
  --num-rates 10 \
  --duration 120s \
  --warmup 30s \
  --dataset misakago/test \
  --dataset-file data.json \
  --decode-options "num_tokens=200,max_tokens=220,min_tokens=180,variance=10"
```

### 解决方案 2：检查 GPUStack 日志

```bash
# 查看 GPUStack 的日志，了解模型加载和请求处理情况
# 日志位置取决于你的 GPUStack 安装方式
journalctl -u gpustack -f
# 或
docker logs <gpustack-container> -f
```

### 解决方案 3：测试基础 vLLM API

如果 GPUStack 有问题，可以直接测试底层的 vLLM：

```bash
# 找到 vLLM 的实际端口（通常是 8000 或 8001）
curl http://localhost:8000/v1/models
curl http://localhost:8001/v1/models

# 测试直接请求
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-vl-8b-instruct",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 50
  }'
```

### 解决方案 4：使用文本模型进行测试

如果问题是 Qwen3-VL 特有的，可以先用纯文本模型测试：

```bash
# 使用 Qwen2.5 或其他文本模型测试
inference-benchmarker \
  --tokenizer-name Qwen/Qwen2.5-7B-Instruct \
  --model-name qwen2.5-7b-instruct \
  --url http://localhost:8001 \
  --api-key gpustack_d521a91e37db5823_542fb6d87249361f5133216132800e4e \
  --benchmark-kind sweep \
  --num-rates 10 \
  --duration 120s \
  --warmup 30s \
  --dataset misakago/test \
  --dataset-file data.json \
  --decode-options "num_tokens=200,max_tokens=220,min_tokens=180,variance=10"
```

## 已知问题

### Qwen3-VL + vLLM 兼容性
- vLLM 0.5.0+ 对 Qwen3-VL 有更好的支持
- 某些版本可能需要额外的环境变量
- 多模态模型可能需要特殊的消息格式

### GPUStack 特定问题
- 模型名称可能与部署名称不同
- API key 格式必须正确
- 某些 GPUStack 版本的流式 API 有 bug

## 获取更多信息

运行诊断脚本后，如果问题仍然存在，请提供：
1. 诊断脚本的完整输出
2. GPUStack 的版本
3. vLLM 的版本
4. 模型的加载日志
5. 任何错误消息

## 临时解决方案

如果无法立即解决，可以使用修复后的代码版本，它会：
1. 在 max_tokens 未指定时使用默认值 512
2. 当 choices 为空时记录详细日志而不是崩溃
3. 记录原始响应数据用于调试

这样至少可以看到详细的错误信息，帮助进一步诊断。
