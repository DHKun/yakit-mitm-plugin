# agent.md — 基于 Yakit 生态的智能流量辅助检测插件

> 本文件是**规划与约束层**，不含业务代码。下一阶段 AI 依据它 + `IMPLEMENTATION_PLAN.md` 直接开工，`AI_INIT.md` 是可直接粘贴的初始化指令。

## 1. 定位
基于 Yakit MITM 流量热加载脚本，实现智能参数启发式提取、LLM Fuzz 字典生成与差异重放验证。符合官方 Schema 上架标准。

## 2. 技术选型
- **主语言**：yaklang（Yakit 插件官方语言，热加载）
- **辅助**：Go（如需编译型性能组件）
- **LLM**：内网模型或 OpenAI 兼容 API，走统一 `ai/payload_agent.yak` 封装。
- **集成**：Yakit MITM 热加载钩子 **`mirrorFilteredHTTPFlow`**（官方推荐，自动过滤 js/css/图片等静态资源流量；`mirrorHTTPFlow` 是全量镜像，一般不要用）。注册后需在脚本内调用 `yakit.AutoInitYakit()` 才能与 GUI 实时交互。
- **参数兼容**：入口同时声明 `cli.*` 表单参数并读取全局 `MITM_PARAMS`；热加载注入值覆盖 CLI 默认值，数值统一做边界校验。
- **范围界定**：`simulator.*` 属于模拟点击爆破模块；本项目保持 MITM 流量辅助检测范围。

## 3. 目录架构（模块落位标记）
```
yakit-mitm-plugin/
├── IMPLEMENTATION_PLAN.md   # 工程实施计划
├── AI_INIT.md               # 下游 AI 初始指令（可直接粘贴）
├── agent.md                 # 本文件
├── src/
│   ├── main.yak             # 入口：注册 mirrorFilteredHTTPFlow + AutoInitYakit
│   ├── traffic/             # dedup.yak / prune.yak / struct.yak
│   ├── ai/                  # payload_agent.yak / schema.yak
│   ├── diff/                # comparator.yak（结构化 Diff 判定）
│   ├── runtime/             # sensor_runtime.yak（队列/worker/预算/限流/scope）
│   ├── evidence/            # checker.yak（类型证据 + control 校验）
│   └── ui/                  # panel.yak（yakit.* GUI 调用：Info/SetProgress/表格）
├── README.md                # 上架文档（安装/使用/截图）
└── test/                    # test_dedup.yak / test_diff.yak
```
> **元数据（已确认）**：插件元数据（模块类型/名称/描述/作者/Tags）在 **GUI 创建插件时直接配置**并随代码入库（官方标注均非必填）；**不存在也不要求 `yakit.json`/`yak.yaml`/manifest**，本项目**不写任何元数据清单文件**（参考 [插件仓库](https://yaklang.com/products/Plugin-repository/)）。公开上架需登录 + 仅原创，公开需管理员审核（参考 [商店指南](https://yaklang.io/blog/yakit-plugin-store-guide/)）。
>
> **运行时兼容策略**：插件仓库场景使用 `cli.*` 表单；热加载/批量启用场景可通过 `MITM_PARAMS` 注入同名字符串参数。

## 4. 状态机（单条流量）
```
CAPTURED → DEDUP(同构则丢弃) → PRUNE(剪枝) → PAYLOAD_GEN → DIFF → DISPLAY
```
LLM 生成失败/超时 → `fallback_dict`（内置字典）降级，保证主链路不中断。

## 5. AI 交互硬约束
- **LLM 只提候选，Diff 实证才是判定**：候选若无 `expected_diff_signature` 直接丢弃。
- **防幻觉**：无论 AI 还是字典，最终都过 Diff 闸门；`confidence ≤ 0.3` 表示"无把握"。
- **防死循环**：单参数候选上限 + 重放超时上限；避免对同一 payload 重复重放。

## 6. 关键算法与验收
- **去重**：`fingerprint = md5(method + 规范化URL + 参数名集合排序 + 参数类型)`，先剥离时间戳/随机参数。验收：100 条同构流量去重后 ≤10 条。
- **剪枝**：白名单放行（id/page），黑名单剥离（timestamp/csrf/nonce）。验收：剪枝率 ≥60%。
- **Diff 判定**：`diff_score = 变化段长度 / 总长`，先归一化时间戳/换行等噪声；阈值 >0.05 且含语义变化 → `differential`。

## 7. 交付
- 首周完成"截获→去重→剪枝"，次周接 LLM 生成 + Diff 实证 + 面板；末尾补 README 上架资料。
- 满足 Yakit 商店上架工程质量（Schema 合规 + README 可复现）。

## 8. 边界
- 不改 Yakit 本体；不在插件内落盘明文敏感数据。
- 未经 Diff 实证的 payload 不得标记"有效"。
- 重放流量走插件内发起的独立 HTTP 请求（`poc.*` 或 `http.*`），不依赖用户正在浏览的那条连接，避免影响正常浏览。
- 范围保持在 MITM 流量辅助检测；参数同时兼容 `cli.*` 与 `MITM_PARAMS`。
- **不写任何元数据 manifest**（`yakit.json`/`yak.yaml` 均不存在，见 §3 已确认说明）。
