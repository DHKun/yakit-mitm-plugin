#!/usr/bin/env bash
# 运行全部单元/集成测试（需本机安装 yak 引擎）
set -e
cd "$(dirname "$0")/../src"
for t in test_dedup test_prune test_diff test_ai test_e2e; do
    echo "===== $t ====="
    yak "../test/${t}.yak" 2>&1 | grep -vE 'irify|vm_exec|yakit:|printer:|tcp_serve|risk:|bot' || true
done
