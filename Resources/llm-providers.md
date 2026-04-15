# LLM Provider 配置文件

> **重要提示**：此文件包含你的 API Key，请妥善保管，不要提交到 Git 仓库！

## 快速开始

1. 打开 `Resources/llm-providers.json` 文件
2. 找到对应 Provider 的 `apiKey` 字段
3. 将你的 API Key 填入引号内（替换 placeholder 文本）
4. 保存文件
5. 在应用设置中选择对应的 Provider

### 示例

```json
{
  "providers": [
    {
      "id": "bailian",
      "name": "阿里云百炼",
      "apiKey": "sk-xxxxxxxxxxxxxxxxxxxxxxxx"
    }
  ]
}
```

## 配置结构

### providers 数组

每个 Provider 包含以下字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | Provider 唯一标识符（代码中使用） |
| `name` | string | 显示名称（UI 中显示） |
| `enabled` | boolean | 是否启用此 Provider |
| `defaultModel` | string | 默认模型名称 |
| `endpoint` | string | API 请求地址 |
| `apiKey` | string | **你的 API Key（在此填写）** |
| `description` | string | 描述文案（UI 中显示） |

### fallbackChain 对象

| 字段 | 类型 | 说明 |
|------|------|------|
| `enabled` | boolean | 是否启用 Fallback 链模式 |
| `providerOrder` | string[] | Provider 尝试顺序（使用 id） |
| `stopOnFirstSuccess` | boolean | 成功后是否停止 |
| `minOverlapScore` | number | 最小重叠分数阈值（0.0-1.0） |

### globalSettings 对象

| 字段 | 类型 | 说明 |
|------|------|------|
| `strictModeEnabled` | boolean | 是否启用严格模式验证 |
| `aiEnabled` | boolean | 是否启用 AI 后处理功能 |
| `agentName` | string | Agent 名称 |
| `aiIterations` | number | AI 迭代次数 |

---

## API Key 获取指南

### 阿里云百炼
- 平台地址：https://dashscope.console.aliyun.com/
- API Key 管理：控制台 > API Key 管理
- 文档：https://help.aliyun.com/zh/dashscope/
- 免费额度：新用户有免费试用额度

### MiniMax
- 平台地址：https://platform.minimaxi.com/
- API Key 管理：控制台 > API Key 管理
- 文档：https://platform.minimaxi.com/document/guide
- 免费额度：注册用户有免费额度

### 智谱 AI
- 平台地址：https://open.bigmodel.cn/
- API Key 管理：控制台 > API Key 管理
- 文档：https://open.bigmodel.cn/dev/api
- 免费额度：新用户有免费试用额度

---

## Git 安全提醒

⚠️ **重要**：请将 `Resources/llm-providers.json` 添加到 `.gitignore`，避免 API Key 泄露！

```bash
# .gitignore
Resources/llm-providers.json
```

如果已经提交到 Git，请立即：
1. 删除 Git 历史中的敏感数据
2. 重置 API Key（在对应平台重新生成）
