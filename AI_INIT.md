# AI_INIT — Yakit 智能流量辅助检测插件 初始指令

> 下游 AI 进入本目录时粘贴以下【正文块】即开工。本目录只含规划层文档（无业务代码），由下游 AI 依据 plan 落地实现。

---

【正文块】
你是一个 Yakit 插件开发工程师，使用 yaklang，遵循 Yakit MITM 热加载机制（`yakplugin`）。当前目录 `/data/Projects/yakit-mitm-plugin/`。

【开工前先读】
1. `agent.md` — 定位 / 选型 / 状态机 / AI 约束 / 边界（尤其 **§3 的"元数据已确认"说明与"待实测点"**）。
2. `IMPLEMENTATION_PLAN.md` — 数据结构 / 关键算法 / 分阶段路线图 / 简历亮点。

【关键事实（已核实，勿改）】
- MITM 流量镜像钩子用 **`mirrorFilteredHTTPFlow`**（官方推荐，自动过滤静态资源），**不要用 `mirrorHTTPFlow`**。
- 钩子签名：`func(isHttps bool, url string, req []byte, rsp []byte, body []byte)`。
- 脚本需调用 **`yakit.AutoInitYakit()`** 才能与 GUI 实时交互。
- **参数声明按插件类型分流**：官方只对**原生 Yak 模块**写明 `cli.*` + `cli.check()`（参考"模拟点击爆破"插件）。**本项目是 MITM 热加载插件**——MITM 类插件的模块类型选项与参数机制（`MITM_PARAMS` 还是 `cli.*`）官方文档**未给出权威结论**，属实现时需对照实际 Yakit GUI 验证的点；**未验证前先按 `MITM_PARAMS`（取值 string，需自行 `parseInt`/`parseBool`）处理，不要混用 `cli.*`**。
- `yakit.AutoInitYakit()` 必须在入口调用；与 GUI 交互用 `yakit.Info` / `yakit.Error` / `yakit.SetProgress` 等，不要用裸 `print`。
- **`simulator.*` 是"模拟点击爆破"模块（`simulator.HttpBruteForce` 等），与本项目"流量辅助检测"无关，仅作 Yakit 编程范式参考（cli 声明/分组/output 回传），不采用、不引入。**

【元数据 — 已确认，不要造文件】
- **无 manifest**：插件元数据（模块类型/名称/描述/作者/Tags）在 **GUI 创建插件时直接配置**并随代码入库（官方标注均非必填）；**不存在 `yakit.json`/`yak.yaml`**。**不要写任何元数据清单文件。**
- **上架**：需登录 + **仅原创**；选**私密**（不上架）或**公开**（需管理员审核）。进官方仓库需联系 yaklang.io 团队。

【实现时需对照 GUI 验证的点】
- MITM 类插件在"模块类型"里如何选、参数机制是 `MITM_PARAMS` 还是 `cli.*`——官方文档未给出权威结论，实现第一步在 Yakit 里如实测一遍再定。

【上下文规则】
- 只改 `src/` 与 `README.md`，不改 Yakit 本体；不在插件内落盘明文敏感数据。
- 所有 LLM 调用走 `src/ai/payload_agent.yak` 统一封装，禁止各文件直连。
- 未经 Diff 实证的 payload 不得标记为"有效"；重放走插件内独立 HTTP 请求，不阻塞用户浏览。

【第一阶段启动动作】
1. 先在 Yakit 里实测"MITM 类插件的模块类型选项 + 参数机制（`MITM_PARAMS` 还是 `cli.*`）"，结合实测再动工（元数据本身已确认无需 manifest，无需再纠结该点）。
2. 实现 `src/traffic/struct.yak` 的 TrafficRecord 字段与 schema。
3. 实现 `src/traffic/dedup.yak` 的 fingerprint（剥离时间戳/随机参数后 md5）。
4. 写 `test/test_dedup.yak`：20 条同构 + 5 条异构流量，断言去重结果。
5. 完成后返回：改动文件、测试命令与结果、以及该实测结论。

【不要做】
- 不引入方案外能力、不强行加功能、不处理与"流量辅助检测"无关的需求。
- **不要实现或模拟"模拟点击爆破 / simulator / 登录爆破"类能力**——那不属于本项目。
- **不要写任何元数据 manifest 文件**（已确认不存在 `yakit.json`/`yak.yaml`）。
