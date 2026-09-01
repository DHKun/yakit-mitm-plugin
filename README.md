# yakit-ai-sensor — 基于 Yakit MITM 的智能流量辅助检测插件

> 被动捕获浏览流量 → 去重降噪 → 参数剪枝 → LLM 生成 Fuzz 候选 → 差异重放实证 → 面板仅报告有差异者。
>
> LLM 只提候选，**差异重放实证才是判定**。未经 Diff 实证的 payload 永远不会被标记为有效。

## 这是什么

一个跑在 Yakit「MITM 交互劫持」里的热加载插件（yaklang 编写）。你正常浏览目标站点，插件在镜像流里：

1. **截获**（`mirrorFilteredHTTPFlow`，自动过滤 js/css/图片等静态资源）
2. **去重**：剥离时间戳/随机参数后按 `md5(method + 规范化路径 + 参数名:类型集合)` 计算指纹，同构请求只保留首条（100 条同构流量 → 1 条）
3. **剪枝**：黑名单剥离 csrf/session/token/password 等破坏语义的参数，白名单放行 id/page/keyword 等高价值参数（真实混合参数集剪枝率 ≈ 76%）
4. **候选生成**：LLM（OpenAI 兼容 API）为每个参数生成 ≤3 个 payload 候选；LLM 未配置/失败/超时自动降级内置字典，主链路不中断
5. **差异实证**：插件内独立发起 HTTP 重放（不占用、不阻塞你正在浏览的连接），对比基线响应与变体响应——先归一化时间戳/随机数/会话噪声，再按行计算 `diff_score = 变化段长度/总长`
6. **展示**：只有 verdict=differential 的判定进结果表 + Yakit 风险页；no_diff/noise 只进日志

## 架构

```
CAPTURED → DEDUP(同构丢弃) → PRUNE(剪枝) → PAYLOAD_GEN(LLM/字典) → DIFF(重放实证) → DISPLAY(仅报差异)
```

```
src/
├── main.yak             # 入口：cli 参数声明 + mirrorFilteredHTTPFlow 注册 + 状态机
├── traffic/
│   ├── struct.yak       # TrafficRecord / PayloadCandidate / DiffResult
│   ├── dedup.yak        # 指纹计算（剥离时间戳/随机参数后 md5）
│   └── prune.yak        # 白名单放行 / 黑名单剥离
├── ai/
│   ├── schema.yak       # System Prompt（硬约束）+ 内置降级字典
│   └── payload_agent.yak# LLM 统一封装：strict JSON 解析、候选校验、降级、失败计数
├── diff/
│   └── comparator.yak   # 归一化 + 行级 diff + diff_score + verdict
└── ui/
    └── panel.yak        # 状态卡 / 结果表 / 风险记录 / 日志分流
```

## 安装

### 方式 A：插件仓库导入（推荐）

1. 打开 Yakit → 插件仓库 → 新建插件
2. 脚本类型选 **Yak-MITM 模块**，粘贴 `src/main.yak` 全部内容
3. 把 `src/` 下其余 `.yak` 文件保持与本仓库相同的相对目录结构放在 Yakit 引擎可访问的路径（插件加载时 `include` 按相对路径解析）
4. 保存后在 MITM 交互劫持 → 插件页启用

### 方式 B：热加载页直接粘贴

MITM 交互劫持 → 热加载页粘贴 `src/main.yak`，把文件头部的 `include` 改成你机器上的绝对路径，点击「热加载」。

## 使用

1. 配置 Yakit MITM 证书并启动交互劫持
2. 启用本插件（带参数插件，表单里可配置）：

| 参数 | 默认 | 说明 |
|---|---|---|
| `llm-base-url` | 空 | OpenAI 兼容 API 地址（如 `https://api.openai.com/v1` 或内网网关）。留空 = 只走内置字典 |
| `llm-api-key` | 空 | API 密钥 |
| `llm-model` | `gpt-4o-mini` | 模型名 |
| `max-candidates` | 3 | 单参数候选上限（防死循环） |
| `replay-timeout` | 8 | 单次重放超时（秒） |
| `replay-total-limit` | 60 | 会话重放总上限（防止对目标过度打点） |
| `max-body-preview` | 512 | 记录的响应体预览长度 |

3. 正常浏览目标站点。顶部状态卡实时显示 `截获 N | 去重保留 N | 候选 N | 实证差异 N`
4. 有实证差异时，结果表输出 URL/参数/Payload/diff_score/预期差异特征，并写入 Yakit 风险页

## 测试

本机安装 [yak 引擎](https://github.com/yaklang/yaklang/releases)后：

```bash
bash test/run_all.sh
```

5 个测试文件全部自带 Mock（Mock LLM 服务 + Mock 易受攻击目标），**不出网**：

| 测试 | 覆盖 |
|---|---|
| `test_dedup.yak` | 20 条同构折叠为 1 / 5 条异构保留 / 噪声参数不参与指纹 / 100 条同构 ≤10 |
| `test_prune.yak` | 黑名单剪除 / 白名单保留 / 混合集剪枝率 ≥60% / 噪声值剪除 |
| `test_diff.yak` | 相同响应 no_diff / SQL 错误 differential / 纯噪声归一化 / 长响应稀疏变化定位 |
| `test_ai.yak` | LLM 正常解析 / 缺 signature 候选丢弃 / 空数组放弃 / 非 JSON 降级 / 字典分流 / 失败计数 |
| `test_e2e.yak` | 完整状态机：注入触发 differential / 无害 payload no_diff / 同构去重 / 黑名单不进候选 |

单测示例（其余同理，注意从 `src/` 目录运行，`include` 是相对 CWD 解析的）：

```bash
cd src && yak ../test/test_dedup.yak
```

## 设计约束（为什么这样做）

- **防幻觉**：LLM 只提候选，每条候选必须携带 `expected_diff_signature`（预期可观测差异），否则直接丢弃；最终是否成立完全由差异重放实证决定
- **降级链路**：LLM 失败计数 ≥3 后本会话直接走内置字典，字典候选同样带预期差异特征、同样过 Diff 闸门
- **不打扰浏览**：重放走插件内独立发起的 `poc.HTTP` 请求；`mirrorFilteredHTTPFlow` 镜像钩子天然不阻塞代理
- **过度打点保护**：单参数候选上限 + 会话重放总上限 + 同构请求只测一次
- **无 manifest**：插件元数据（模块类型/名称/描述/Tags）在 Yakit GUI 创建插件时配置，本仓库不含也不需要任何元数据清单文件

## 免责声明

仅用于授权安全测试与学习研究。对未授权目标使用本工具产生的后果由使用者自行承担。

## 许可

MIT
