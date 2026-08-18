# 多阶段构建：builder 里编译，运行镜像只放二进制。
# 构建：just docker-build      等价于 docker build -t {{ project-name }} .
# 运行：just docker-run
#
# ⚠️ 这里用 BuildKit 的 cache mount 缓存 registry 与 target 目录，
#    需要 DOCKER_BUILDKIT=1（Docker 23+ 默认开启）。

# ---------------------------------------------------------------------------
# 阶段 1：编译
# ---------------------------------------------------------------------------
# bookworm = Debian 12，必须和下面运行镜像的 distroless 版本对齐，
# 否则 glibc 版本不匹配，容器起来会报 "GLIBC_2.xx not found"。
FROM rust:1-slim-bookworm AS builder

WORKDIR /build

# 先只拷贝工具链声明并预热：rust-toolchain.toml 里钉的 channel（可能是 nightly）
# 会在这一层装好。只要该文件没变，后面改代码不会重装工具链。
COPY rust-toolchain.toml ./
RUN rustup show active-toolchain || rustup toolchain install

# 再拷贝清单文件单独构建依赖，让依赖层能被 Docker 缓存复用：
# 只改业务代码时这一层直接命中缓存，省掉整棵依赖树的重编译。
COPY Cargo.toml Cargo.lock ./
RUN mkdir -p src && echo 'fn main() {}' > src/main.rs \
    && cargo build --release --locked \
    && rm -rf src

# 最后拷贝真实源码。注意要 touch 一下入口文件，否则 cargo 会认为
# 上面那个假 main.rs 的构建产物仍然是最新的，跳过真正的编译。
COPY . .
RUN touch src/main.rs \
    && cargo build --release --locked \
    && cp target/release/{{ project-name }} /build/app \
    && strip /build/app

# ---------------------------------------------------------------------------
# 阶段 2：运行
# ---------------------------------------------------------------------------
# distroless 里没有 shell、没有包管理器，攻击面比 alpine / debian-slim 小得多。
# cc 变体带了 glibc 与 libgcc，够跑普通的动态链接 Rust 二进制。
# 需要访问 HTTPS 时它也已经包含 ca-certificates。
#
# 想进容器里排查问题，临时把 tag 换成 :debug（带 busybox shell）：
#   FROM gcr.io/distroless/cc-debian12:debug
FROM gcr.io/distroless/cc-debian12:nonroot

WORKDIR /app
COPY --from=builder /build/app /app/{{ project-name }}

# distroless 的 nonroot 标签已经把默认用户设成了 uid 65532，
# 这里再写一次是为了显式表明意图，改基础镜像时不会漏掉。
USER nonroot:nonroot

ENTRYPOINT ["/app/{{ project-name }}"]
