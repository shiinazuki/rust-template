# Docker 相关命令。由根 justfile 的 `import? 'docker.just'` 可选加载：
# 生成项目时没选 Docker，这个文件不存在，import? 静默跳过。
#
# ⚠️ 本文件在 cargo-generate.toml 的 exclude 里（不做 liquid 替换），
#    所以镜像名不能用 {{ project-name }}，改成从 Cargo.toml 里读。
#
# ⚠️ `pkg` 定义在根 justfile 里，这边不要再定义一次——import 之后是同一个命名空间，
#    重复定义会让 just 直接报 "variable has multiple definitions"，所有命令都用不了。

version := `grep -m1 '^version' Cargo.toml | sed -E 's/.*"(.*)".*/\1/'`
revision := `git rev-parse --short HEAD 2>/dev/null || echo unknown`
tag := "latest"

[group('docker')]
[doc('构建镜像（同时打 latest 与版本号两个 tag）')]
docker-build:
    #!/usr/bin/env bash
    set -euo pipefail
    # --locked 构建要求 Cargo.lock 是最新的，先在宿主机确认一次，
    # 免得排队等几分钟才在容器里看到「lock file needs to be updated」。
    cargo check --locked --quiet
    DOCKER_BUILDKIT=1 docker build \
        --build-arg VERSION="{{ version }}" \
        --build-arg REVISION="{{ revision }}" \
        -t "{{ pkg }}:{{ tag }}" \
        -t "{{ pkg }}:{{ version }}" \
        .
    docker images --format '  {{{{.Repository}}}}:{{{{.Tag}}}}  {{{{.Size}}}}' | grep "^  {{ pkg }}:" || true

[group('docker')]
[doc('运行镜像，额外参数透传给程序：just docker-run -- --help')]
docker-run *args:
    docker run --rm -it {{ pkg }}:{{ tag }} {{ args }}

[group('docker')]
[doc('用 dive 分析镜像分层体积（需要 dive）')]
docker-inspect:
    dive {{ pkg }}:{{ tag }}

[group('docker')]
[doc('扫描镜像里的已知漏洞（需要 trivy）')]
docker-scan:
    trivy image --severity HIGH,CRITICAL --ignore-unfixed {{ pkg }}:{{ tag }}

[group('docker')]
[doc('删除本地构建的镜像')]
docker-clean:
    -docker rmi {{ pkg }}:{{ tag }} {{ pkg }}:{{ version }}
