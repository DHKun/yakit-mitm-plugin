# Changelog

## Unreleased

### Added

- `SensorRuntime`：固定 worker 池、有界队列、统一重放预算、per-origin 令牌桶、Host scope、GET/POST 方法白名单和并发安全 metrics。
- 指纹去重缓存与 origin 限流桶采用固定容量淘汰，长期高基数流量保持内存有界。
- 按漏洞类型匹配的结构化证据层，以及 control 重放稳定性校验。
- AI payload 控制字符清洗、长度限制和 `vuln_hint` 白名单。
- Runtime、evidence 与完整主链路测试；所有测试仅使用纯函数或本地 Mock 服务。
- GitHub Actions：固定 Yak release、SHA256 校验、ShellCheck、完整测试和构建产物。

### Changed

- `mirrorFilteredHTTPFlow` 只执行非阻塞队列提交；队列满时记录并丢弃新任务。
- `replay-total-limit` 现在覆盖 baseline、variant、control 三类主动请求。
- 风险生成条件收紧为“类型匹配的结构化证据 + 稳定 control”；普通动态差异进入 observation 日志。
- 无 `scope-hosts` 时，保留地址、内网地址和云元数据地址默认拒绝主动重放。
- 主动探测方法限制为 GET、POST。

### Compatibility

- 面板状态卡和结果表字段已更新，旧版 `实证差异` 指标拆分为 `已确认` 与 `观察`。
- 使用私有地址或本机测试环境时必须显式配置 `scope-hosts`。
