#!/usr/bin/env bash
# run_all.sh — 运行全部 Yak 测试（单元 + 集成），失败时返回非零。
#
# 规则：
# - set -Eeuo pipefail：任何未捕获错误立即失败；管道中 yak 的退出码不会被吞掉。
# - 自动发现 test/test_*.yak（显式列表优先可用 TEST_FILES 覆盖）。
# - 单个测试失败继续跑完剩余测试，最终以非零退出（FAILED 列表汇总）。
# - 每个测试有独立超时（防卡死的 mock 服务拖垮 CI）。
# - 完整输出（含 yak 引擎日志）写入 test/.results/<test>.log，控制台只显示摘要与失败详情。
# - 退出时清理临时结果目录（失败时保留，便于排查）。
#
# 用法：
#   bash test/run_all.sh                  # 全部测试
#   TEST_FILES="test_dedup" bash test/run_all.sh   # 指定测试（不含路径与扩展名）

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/../src"
RESULTS_DIR="${SCRIPT_DIR}/.results"
PER_TEST_TIMEOUT="${PER_TEST_TIMEOUT:-120}"   # 秒；e2e 内含 mock 服务与重放
YAK_BIN="${YAK_BIN:-yak}"

# ---------- yak 引擎检查 ----------
if ! command -v "${YAK_BIN}" >/dev/null 2>&1; then
    echo "ERROR: yak engine not found in PATH (set YAK_BIN to override)" >&2
    exit 2
fi

cd "${SRC_DIR}"
mkdir -p "${RESULTS_DIR}"

# ---------- 测试发现 ----------
# 显式环境变量 > 自动发现 test/test_*.yak（保证新增测试无需改本脚本）
declare -a TESTS=()
if [[ -n "${TEST_FILES:-}" ]]; then
    read -r -a requested_tests <<< "${TEST_FILES}"
    for t in "${requested_tests[@]}"; do
        TESTS+=("${t%.yak}")
    done
else
    shopt -s nullglob
    for f in "${SCRIPT_DIR}"/test_*.yak; do
        base="$(basename "${f}" .yak)"
        TESTS+=("${base}")
    done
    shopt -u nullglob
fi

if [[ ${#TESTS[@]} -eq 0 ]]; then
    echo "ERROR: no test files found (test/test_*.yak)" >&2
    exit 2
fi

echo "Discovered ${#TESTS[@]} test(s): ${TESTS[*]}"
echo

# ---------- 执行 ----------
PASSED=()
FAILED=()
TIMED_OUT=()

cleanup() {
    # 成功时清理结果目录；失败时保留日志便于排查
    if [[ ${#FAILED[@]} -eq 0 && ${#TIMED_OUT[@]} -eq 0 ]]; then
        rm -rf "${RESULTS_DIR}"
    fi
}
trap cleanup EXIT

for t in "${TESTS[@]}"; do
    echo "===== ${t} ====="
    log_file="${RESULTS_DIR}/${t}.log"
    start_ts=$(date +%s)
    # yak 的原始退出码必须保留：不用管道接 grep（管道会掩盖退出码），
    # 引擎噪声日志写入 log 文件，控制台只回显摘要。
    if timeout "${PER_TEST_TIMEOUT}" "${YAK_BIN}" "../test/${t}.yak" >"${log_file}" 2>&1; then
        rc=0
    else
        rc=$?
    fi
    elapsed=$(( $(date +%s) - start_ts ))

    if [[ ${rc} -eq 0 ]]; then
        PASSED+=("${t}")
        echo "PASS  ${t} (${elapsed}s)"
        # 成功也回显断言摘要（ok/FAIL 行），让人能看见测试真的在跑
        grep -E '^(ok|FAIL)' "${log_file}" || true
    elif [[ ${rc} -eq 124 ]]; then
        TIMED_OUT+=("${t}")
        echo "TIMEOUT ${t} (>${PER_TEST_TIMEOUT}s)" >&2
    else
        FAILED+=("${t}")
        echo "FAIL  ${t} (exit=${rc}, ${elapsed}s)" >&2
    fi
done

echo
echo "===== summary ====="
echo "passed: ${#PASSED[@]}  failed: ${#FAILED[@]}  timed_out: ${#TIMED_OUT[@]}"

# ---------- 失败详情 ----------
exit_code=0
if [[ ${#TIMED_OUT[@]} -gt 0 ]]; then
    echo "TIMED OUT: ${TIMED_OUT[*]}" >&2
    for t in "${TIMED_OUT[@]}"; do
        echo "--- tail of ${RESULTS_DIR}/${t}.log ---" >&2
        tail -50 "${RESULTS_DIR}/${t}.log" >&2 || true
    done
    exit_code=1
fi
if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "FAILED: ${FAILED[*]}" >&2
    for t in "${FAILED[@]}"; do
        echo "--- full log: ${RESULTS_DIR}/${t}.log ---" >&2
        cat "${RESULTS_DIR}/${t}.log" >&2 || true
    done
    exit_code=1
fi

if [[ ${exit_code} -eq 0 ]]; then
    echo "ALL TESTS PASSED"
fi
exit "${exit_code}"
