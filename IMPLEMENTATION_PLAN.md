# 基于 Yakit 生态的智能流量辅助检测插件 — 工程实施计划

> 定位：基于 Yakit MITM 流量热加载脚本，实现智能参数启发式提取、LLM Fuzz 字典生成与差异重放验证。符合官方 Schema、可上架。

## 1. 技术栈与目录架构
主语言 **yaklang**（Yakit 插件官方语言，热加载），辅助 Go（如需编译型组件）。集成 MITM 热加载钩子 **`mirrorFilteredHTTPFlow`**（官方推荐，自动过滤静态资源；全量镜像 `mirrorHTTPFlow` 一般不用）。

```
yakit-mitm-plugin/
├── agent.md / IMPLEMENTATION_PLAN.md / AI_INIT.md
├── src/
│   ├── main.yak          # 入口，注册 mirrorFilteredHTTPFlow + yakit.AutoInitYakit()；读 MITM_PARAMS，不写 cli.*
│   ├── traffic/          # dedup / prune / struct
│   ├── ai/               # payload_agent / schema
│   ├── diff/             # comparator（结构化 Diff）
│   └── ui/               # panel（yakit.* GUI 调用）
├── README.md             # 上架文档
└── test/
```
> **元数据（已确认，无需 manifest）**：官方 `plugin_create`/`Plugin-repository` 文档明确——插件元数据（模块类型 / 名称 / 简要描述 / 模块作者 / Tags）全部在 **GUI 创建插件时直接配置**并随代码入库，官方标注"均非必填"；**不存在也不要求 `yakit.json`/`yak.yaml`/manifest 文件**。第三方博客的 `yakit.json` 字段（name/version/schema）确认**不可信**。
>
> **公开上架流程（已确认）**：登录 + **仅原创**；上传选**私密**（自己/分享可见，不上架）或**公开**（需**管理员审核**后才在商店展示）。"进官方仓库"需**联系 yaklang.io 团队**，非纯上传。参考 [插件商店使用指南](https://yaklang.io/blog/yakit-plugin-store-guide/)。
>
> **参数声明分流**：官方文档只对**原生 Yak 模块**写明 `cli.*` + `cli.check()`（生态"模拟点击爆破"即此写法，仅作范式参考）。本项目是 **MITM 热加载插件**。**实现时需对照实际 Yakit GUI 验证**：MITM 类插件在创建时的"模块类型"选项、以及参数到底取 `MITM_PARAMS` 还是能用 `cli.*`——官方文档未此给出权威结论，此为运行时参数机制层面的实现点，不阻塞架构。
>
> **范围界定**：`simulator.*`（`simulator.HttpBruteForce` 等）是"模拟点击爆破"模块，**与"流量辅助检测"无关，不采用**。

## 2. 核心数据结构
```jsonc
TrafficRecord: { id, fingerprint:md5(method+规范URL+参数名集合+参数类型), method, url,
                 raw_params[], body_preview, status, resp_len, timestamp }
PayloadCandidate: { id, traffic_id, param, payload, vuln_hint, reason, confidence }
DiffResult: { candidate_id, baseline_hash, variant_hash, diff_score, verdict, diff_regions[] }
```

## 3. 状态机
`CAPTURED → DEDUP(同构丢弃) → PRUNE → PAYLOAD_GEN → DIFF → DISPLAY`；LLM 失败/超时走 `fallback_dict` 降级。

## 4. 数据流 / AI 交互
- 数据流：`mirrorFilteredHTTPFlow` 截获 → 去重 → 剪枝 → 结构化记录 → LLM 生成候选 → 逐个重放（重放走插件内独立 HTTP 请求，不阻塞用户浏览）→ Diff 判定 → 面板仅展示有差异者。
- System Prompt 要点：候选必须给 `expected_diff_signature`；与参数类型无关的 payload 不得推荐；无把握 `confidence≤0.3`；输出 strict JSON，空数组表示建议放弃该参数。
- **防幻觉**：LLM 只提候选，是否成立由 Diff 重放实证；无预期差异特征直接丢弃。

## 5. 关键算法
- 去重：先剥离时间戳/随机参数再哈希，同构请求保留首条。目标：100 条同构 → ≤10 条。
- 剪枝：白名单放行（id/page），黑名单剥离（timestamp/csrf/nonce）。目标：剪枝率 ≥60%。
- Diff：`diff_score = 变化段长度/总长`；先归一化时间戳/换行/空白噪声；阈值 >0.05 且含语义变化 → differential，否则 no_diff/noise。

## 6. 分阶段路线图（2 周）
| 阶段 | 微任务 | 验收 |
|---|---|---|
| Day 1-3 | 设计好 `src/traffic/struct.yak` 的 TrafficRecord + 用 `mirrorFilteredHTTPFlow` 搭骨架 + `AutoInitYakit()`（元数据已确认，GUI 配置即可，无需 manifest） | Yakit 加载并打印流量 |
| Day 4-7 | dedup + prune + 单测 | 100 条同构 ≤10 条；剪枝率 ≥60% |
| Day 8-10 | LLM payload + 重放 + Diff 判定 | Sqli-labs 类环境判定符合预期 |
| Day 11-14 | 面板 + fallback + README 上架 | 文档可复现，误报有基线 |

## 7. 简历亮点
1. 遵循 Yakit 官方 Schema 与热加载机制，达上架标准。
2. LLM 生成候选 + Diff 实证判定，双保险压制幻觉。
3. 流量去重 + 参数剪枝，显著降噪与降低无效重放。

> 量化指标为设计目标，实现阶段实测后写入简历。
