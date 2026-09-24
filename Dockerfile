# 多阶段构建：builder 里编译，运行镜像只放一个二进制。
# 构建：just docker-build      运行：just docker-run
#
# cargo registry 与 target 用 BuildKit 的 cache mount 缓存，在 CI 的全新机器上为空；
# CI 上要缓存可以用 docker/build-push-action 的 cache-from/cache-to=gha，或换成 cargo-chef。

# ---------------------------------------------------------------------------
# 阶段 1：编译
# ---------------------------------------------------------------------------
# Debian 版本（trixie = 13）要与运行镜像的 distroless 一致，否则 glibc 不匹配
FROM rust:1-slim-trixie AS builder

WORKDIR /build

# 按 rust-toolchain.toml 安装工具链，单独成层以便缓存
COPY rust-toolchain.toml ./
RUN rustup show active-toolchain || rustup toolchain install

# cargo-auditable 把依赖清单嵌进二进制，供 `cargo audit bin` 与 trivy（just docker-scan）扫描。
# 不需要时删掉这一层，并把下面的 `cargo auditable build` 改回 `cargo build`。
RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    cargo install --locked cargo-auditable

COPY . .

# cache mount 只在本条 RUN 内存在，产物要在同一条 RUN 里拷出来
RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,target=/build/target,sharing=locked \
    cargo auditable build --release --locked \
    && cp target/release/{{ project-name }} /build/app

# ---------------------------------------------------------------------------
# 阶段 2：运行
# ---------------------------------------------------------------------------
# distroless 的 cc 变体：带 glibc、libgcc 与 ca-certificates，没有 shell。
# 需要 shell 排查时临时换成 :debug 标签。
FROM gcr.io/distroless/cc-debian13:nonroot

# OCI 标准标签，VERSION / REVISION 由 --build-arg 传入
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

# 以非 root 用户（uid 65532）运行
USER nonroot:nonroot

ENTRYPOINT ["/app/{{ project-name }}"]
