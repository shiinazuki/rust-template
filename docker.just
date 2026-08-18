# Docker 相关命令。由根 justfile 的 `import? 'docker.just'` 可选加载：
# 生成项目时没选 Docker，这个文件不存在，import? 静默跳过。
#
# ⚠️ 本文件在 cargo-generate.toml 的 exclude 里（不做 liquid 替换），
#    所以镜像名不能用 {{ project-name }}，改成从 Cargo.toml 里读。

pkg := `grep -m1 '^name' Cargo.toml | sed -E 's/.*"(.*)".*/\1/'`
tag := "latest"

[group('docker')]
[doc('构建镜像')]
docker-build:
    DOCKER_BUILDKIT=1 docker build -t {{ pkg }}:{{ tag }} .

[group('docker')]
[doc('运行镜像，额外参数透传给程序：just docker-run -- --help')]
docker-run *args:
    docker run --rm -it {{ pkg }}:{{ tag }} {{ args }}

[group('docker')]
[doc('用 dive 分析镜像分层体积（需要 dive）')]
docker-inspect:
    dive {{ pkg }}:{{ tag }}

[group('docker')]
[doc('删除本地构建的镜像')]
docker-clean:
    -docker rmi {{ pkg }}:{{ tag }}
