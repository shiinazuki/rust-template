# 多阶段构建：builder 里编译，运行镜像只放一个二进制。
# 构建：just docker-build      运行：just docker-run
#
# ⚠️ 依赖 BuildKit 的 cache mount（Docker 23+ 默认开启，docker.just 里也显式设了
#    DOCKER_BUILDKIT=1）。cache mount 把 cargo registry 与 target 目录挂成持久缓存，
#    改一行代码重新构建时不必重编整棵依赖树。
#
#    代价是这份缓存**不随镜像层走**：在每次都是全新机器的 CI 上它是空的。
#    如果 CI 构建时间成了瓶颈，两条路：
#      1) GitHub Actions 用 docker/build-push-action 的 cache-from/cache-to=gha；
#      2) 换成 cargo-chef，把依赖编译固化成一个真正的镜像层。

# ---------------------------------------------------------------------------
# 阶段 1：编译
# ---------------------------------------------------------------------------
# bookworm = Debian 12，必须和下面运行镜像的 distroless 版本对齐，
# 否则 glibc 版本不匹配，容器起来会报 "GLIBC_2.xx not found"。
FROM rust:1-slim-bookworm AS builder

WORKDIR /build

# 先只拷贝工具链声明并预热：rust-toolchain.toml 里钉的 channel（可能是 nightly）
# 会在这一层装好。只要该文件没变，后面改代码不会重装工具链——这一层是真正的镜像层缓存。
COPY rust-toolchain.toml ./
RUN rustup show active-toolchain || rustup toolchain install

COPY . .

# --locked 要求仓库里有一份最新的 Cargo.lock。刚生成完项目还没跑过 cargo 时它可能
# 不存在（选了依赖开关的话模板会主动删掉过期的那份），先在宿主机 `cargo check` 一次。
#
# cp 必须和 cargo build 在同一个 RUN 里：cache mount 挂载的 /build/target
# 在这条 RUN 结束后就消失了，下一条指令是看不到它的。
RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,target=/build/target,sharing=locked \
    cargo build --release --locked \
    && cp target/release/{{ project-name }} /build/app

# ---------------------------------------------------------------------------
# 阶段 2：运行
# ---------------------------------------------------------------------------
# distroless 里没有 shell、没有包管理器，攻击面比 alpine / debian-slim 小得多。
# cc 变体带了 glibc 与 libgcc，够跑普通的动态链接 Rust 二进制，也自带 ca-certificates。
#
# 想进容器里排查问题，临时把 tag 换成 :debug（带 busybox shell）：
#   FROM gcr.io/distroless/cc-debian12:debug
FROM gcr.io/distroless/cc-debian12:nonroot

# OCI 标准标签。GitHub / GHCR 靠 image.source 把镜像和仓库关联起来，
# 出问题时也能从 `docker inspect` 直接看出这个镜像是哪个 commit 构建的。
ARG VERSION=0.0.0
ARG REVISION=unknown
LABEL org.opencontainers.image.title="{{ project-name }}" \
      org.opencontainers.image.description="{{ description }}" \
      org.opencontainers.image.source="https://github.com/{{ gh-username }}/{{ project-name }}" \
      org.opencontainers.image.licenses="{{ license }}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}"

WORKDIR /app
COPY --from=builder /build/app /app/{{ project-name }}

# 二进制里的 panic 信息默认只有一行，容器里没法 gdb，backtrace 是唯一线索
ENV RUST_BACKTRACE=1

# distroless 的 nonroot 标签已经把默认用户设成了 uid 65532，
# 这里再写一次是为了显式表明意图，换基础镜像时不会漏掉。
USER nonroot:nonroot

ENTRYPOINT ["/app/{{ project-name }}"]
