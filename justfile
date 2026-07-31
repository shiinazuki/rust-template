# 默认执行 check
default: check

# 快速检查代码编译
check:
    cargo check --all-targets --all-features

# 运行测试 (使用 nextest)
test:
    cargo nextest run --all-targets --all-features

# 代码格式化与拼写检查
lint:
    cargo fmt --all -- --check
    cargo clippy --all-targets --all-features -- -D warnings
    typos

# 依赖安全与 License 检查
audit:
    cargo deny check

# 启动后台实时监控 (bacon)
dev:
    bacon
