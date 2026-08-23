# 多阶段构建：builder 里编译，运行镜像只放一个二进制。
# 构建：just docker-build      运行：just docker-run
#
# 用到 BuildKit 的 cache mount（Docker 23+ 默认开启，docker.just 里也显式设了
# DOCKER_BUILDKIT=1），把 cargo registry 与 target 目录挂成持久缓存。
# 这份缓存不随镜像层走，在每次都是全新机器的 CI 上是空的；CI 上要缓存可以用
# docker/build-push-action 的 cache-from/cache-to=gha，或换成 cargo-chef。

# ---------------------------------------------------------------------------
# 阶段 1：编译
# ---------------------------------------------------------------------------
# trixie = Debian 13，必须和下面运行镜像的 distroless 版本对齐，
# 否则 glibc 版本不匹配，容器起来会报 "GLIBC_2.xx not found"。换大版本时两处一起改。
FROM rust:1-slim-trixie AS builder

WORKDIR /build

# 先只拷贝工具链声明并装好 rust-toolchain.toml 里钉的 channel，
# 该文件没变时这一层直接命中镜像层缓存。
COPY rust-toolchain.toml ./
RUN rustup show active-toolchain || rustup toolchain install

# cargo-auditable 把依赖清单编进二进制的一个专用 section，可以直接对着产物查 CVE：
#     cargo audit bin /app/{{ project-name }}
# `just docker-scan` 用的 trivy 也读这份数据。体积代价约 1%，运行时零开销。
# 不需要的话删掉这一层，并把下面的 `cargo auditable build` 改回 `cargo build`。
RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    cargo install --locked cargo-auditable

COPY . .

# --locked 要求仓库里有一份最新的 Cargo.lock，缺了先在宿主机跑一次 `just bootstrap`。
# cp 必须和 cargo build 在同一个 RUN 里：cache mount 挂载的 /build/target
# 在这条 RUN 结束后就消失了。
RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,target=/build/target,sharing=locked \
    cargo auditable build --release --locked \
    && cp target/release/{{ project-name }} /build/app

# ---------------------------------------------------------------------------
# 阶段 2：运行
# ---------------------------------------------------------------------------
# distroless 里没有 shell、没有包管理器；cc 变体带 glibc、libgcc 与 ca-certificates，
# 够跑普通的动态链接 Rust 二进制。
# 想进容器排查问题，临时把 tag 换成 :debug（带 busybox shell）：
#   FROM gcr.io/distroless/cc-debian13:debug
FROM gcr.io/distroless/cc-debian13:nonroot

# OCI 标准标签：镜像仓库靠 image.source 把镜像关联回代码仓库，
# revision 记录构建自哪个 commit。域名跟着生成时选的 CI 平台走。
ARG VERSION=0.0.0
ARG REVISION=unknown
LABEL org.opencontainers.image.title="{{ project-name }}" \
      org.opencontainers.image.description="{{ description }}" \
      org.opencontainers.image.source="https://{% if ci == 'gitlab' %}gitlab.com{% else %}github.com{% endif %}/{{ repo-owner }}/{{ project-name }}" \
      org.opencontainers.image.licenses="{{ license }}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}"

WORKDIR /app
COPY --from=builder /build/app /app/{{ project-name }}

# 打开 panic backtrace
ENV RUST_BACKTRACE=1

# 以非 root 用户运行（distroless 的 nonroot 标签已默认 uid 65532，这里显式写出）
USER nonroot:nonroot

ENTRYPOINT ["/app/{{ project-name }}"]
