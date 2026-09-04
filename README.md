# yakit-ai-sensor — 基于 Yakit MITM 的智能流量辅助检测插件

> 被动捕获浏览流量 → 有界队列 → 去重剪枝 → LLM 生成候选 → 受控重放 → 结构化证据确认。
>
> LLM 只提候选。只有“漏洞类型匹配证据 + 稳定 control 重放”进入 Yakit 风险页；普通动态差异保留为观察日志。

## 这是什么

一个跑在 Yakit「MITM 交互劫持」里的热加载插件（yaklang 编写）。你正常浏览目标站点，插件在镜像流里：

1. **截获**：`mirrorFilteredHTTPFlow` 只向有界队列做非阻塞提交，队列满时记录丢弃指标
2. **去重**：剥离时间戳/随机参数后按 `md5(method + 规范化路径 + 参数名:类型集合)` 计算指纹，同构请求只保留首条（100 条同构流量 → 1 条）
3. **剪枝**：黑名单剥离 csrf/session/token/password 等破坏语义的参数，白名单放行 id/page/keyword 等高价值参数（真实混合参数集剪枝率 ≈ 76%）
4. **候选生成**：LLM（OpenAI 兼容 API）为每个参数生成 ≤3 个 payload 候选；LLM 未配置/失败/超时自动降级内置字典，主链路不中断
5. **受控重放**：baseline、variant、control 全部经过 Host 范围、GET/POST 方法、统一预算和 per-origin 令牌桶
6. **证据确认**：差异必须命中对应漏洞类型的结构化证据；随后用 control 重放排除目标自身漂移
7. **展示**：确认结果进入表格和 Yakit 风险页；普通动态差异进入 observation 日志

## 架构

```
CAPTURED → QUEUE → DEDUP → PRUNE → PAYLOAD_GEN → GUARDED_REPLAY → EVIDENCE → DISPLAY
```

```
src/
├── main.yak             # 入口：参数解析、Hook 注册、状态机与统一重放出口
├── traffic/
│   ├── struct.yak       # TrafficRecord / PayloadCandidate / DiffResult
│   ├── dedup.yak        # 指纹计算（剥离时间戳/随机参数后 md5）
│   └── prune.yak        # 白名单放行 / 黑名单剥离
├── ai/
│   ├── schema.yak       # System Prompt（硬约束）+ 内置降级字典
│   └── payload_agent.yak# LLM 统一封装：strict JSON 解析、候选校验、降级、失败计数
├── diff/
│   └── comparator.yak   # 归一化 + 行级 diff + diff_score + verdict
├── runtime/
│   └── sensor_runtime.yak # 有界 worker 池、预算、限流、scope/method 门禁、metrics
├── evidence/
│   └── checker.yak      # 按漏洞类型匹配结构化证据 + control 稳定性检查
└── ui/
    └── panel.yak        # verified 风险与 observation 日志分流
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
| `replay-total-limit` | 60 | baseline、variant、control 共用的一次性预算 |
| `workers` | 2 | 固定分析 worker 数量 |
| `queue-size` | 256 | 镜像任务队列容量；满载时新任务快速丢弃 |
| `replay-rps` | 5 | 每个 origin 的每秒令牌数与突发容量 |
| `max-origins` | 256 | 最多保留的 origin 限流桶数量，超出后淘汰旧桶 |
| `scope-hosts` | 空 | 逗号分隔的精确 Host 白名单；空值模式拒绝保留、内网和元数据地址 |
| `max-payload-len` | 256 | AI 和内置字典 payload 长度上限 |
| `time-diff-ms` | 2000 | variant 相对 baseline 的时延证据阈值 |
| `max-body-preview` | 512 | 记录的响应体预览长度 |

私有地址或本机授权环境需要显式填写 `scope-hosts`，例如 `127.0.0.1,app.internal`。

3. 正常浏览目标站点。状态卡显示截获、去重、候选、确认、观察、重放和队列丢弃数
4. 结构化证据与 control 均通过时，结果表输出证据类型并写入 Yakit 风险页

## 测试

本机安装 [yak 引擎](https://github.com/yaklang/yaklang/releases)后：

```bash
bash test/run_all.sh
```

7 个测试文件全部使用纯函数或本地 Mock 服务，测试 payload **不访问公网**：

| 测试 | 覆盖 |
|---|---|
| `test_dedup.yak` | 20 条同构折叠为 1 / 5 条异构保留 / 噪声参数不参与指纹 / 100 条同构 ≤10 |
| `test_prune.yak` | 黑名单剪除 / 白名单保留 / 混合集剪枝率 ≥60% / 噪声值剪除 |
| `test_diff.yak` | 相同响应 no_diff / SQL 错误 differential / 纯噪声归一化 / 长响应稀疏变化定位 |
| `test_ai.yak` | LLM 解析 / 降级 / payload 清洗与长度限制 / hint 白名单 / 并发状态保护 |
| `test_evidence.yak` | SQLi/XSS/SSTI/LFI/CMDi/logic 证据 / signature 交叉校验 / control 稳定性 |
| `test_runtime.yak` | 有界队列 / worker / 并发 metrics / 预算 / 限流 / scope / method |
| `test_e2e.yak` | verified 与 observation 分流 / Hook→队列 / 统一预算 / scope、method 门禁 |

单测示例（其余同理，注意从 `src/` 目录运行，`include` 是相对 CWD 解析的）：

```bash
cd src && yak ../test/test_dedup.yak
```

## 设计约束（为什么这样做）

- **证据优先**：`differential` 只是触发证据检查；风险确认要求漏洞类型匹配证据与稳定 control
- **降级链路**：LLM 失败计数 ≥3 后本会话直接走内置字典，字典候选同样带预期差异特征、同样过 Diff 闸门
- **并发隔离**：Hook 只提交任务；固定 worker 池承担 LLM、Diff 与重放，所有计数和状态均并发安全
- **有界状态**：任务后备存储、流量指纹缓存和 origin 限流桶都有固定容量
- **主动请求保护**：所有重放统一经过 scope、GET/POST 方法、预算、per-origin 限流
- **AI 输入约束**：payload 剥离控制字符、限制长度，`vuln_hint` 经过白名单归一化
- **测试可靠性**：测试脚本保留 Yak 原始退出码，任一测试失败都会让本地命令和 CI 返回非零
- **无 manifest**：插件元数据（模块类型/名称/描述/Tags）在 Yakit GUI 创建插件时配置，本仓库不含也不需要任何元数据清单文件

## 免责声明

仅用于授权安全测试与学习研究。对未授权目标使用本工具产生的后果由使用者自行承担。

## 许可

MIT
