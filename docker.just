# Docker 相关命令，由根 justfile 导入；镜像名用根 justfile 里的 `pkg`。

version := `grep -m1 '^version' Cargo.toml | sed -E 's/.*"(.*)".*/\1/'`
revision := `git rev-parse --short HEAD 2>/dev/null || echo unknown`
tag := "latest"

[group('docker')]
[doc('构建镜像（同时打 latest 与版本号两个 tag）')]
docker-build:
    #!/usr/bin/env bash
    set -euo pipefail
    # 先在宿主机确认 Cargo.lock 是最新的
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
