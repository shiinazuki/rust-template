# 安全策略

## 支持的版本

安全修复只跟进最新的发布版本。请先升级到最新版再报告问题。

## 如何报告漏洞

**请不要开公开 issue。** 公开的漏洞描述在补丁发布前就会被人利用。

请走{% if ci == 'gitlab' %} GitLab 的私密报告流程：

1. 新建一个 [issue](https://gitlab.com/{{ repo-owner }}/{{ project-name }}/-/issues/new)，
   **提交前务必勾选 "This issue is confidential"**——不勾的话它就是一个公开 issue
2. 描述问题、影响范围，以及最小复现步骤{% else %} GitHub 的私密报告流程：

1. 打开 [Security Advisories](https://github.com/{{ repo-owner }}/{{ project-name }}/security/advisories/new)
2. 描述问题、影响范围，以及最小复现步骤{% endif %}

如果那个页面不可用，直接私信仓库维护者。

## 我们的承诺

- **3 个工作日**内确认收到；
- **10 个工作日**内给出初步评估（是否成立、严重程度、大致修复计划）；
- 修复发布后在安全公告里致谢报告者（你也可以要求匿名）。

## 本项目已有的防线

供参考，也欢迎指出其中的漏洞：

- `cargo deny` 在每次改动上检查依赖的安全公告、协议合规与来源{% if ci == 'github' %}，另有每日定时扫描
  （代码没动，风险也会变——新披露的 CVE 只有定时任务能发现）{% elsif ci == 'gitlab' %}
  （建议再到 CI/CD → Schedules 配一条每日定时流水线：代码没动，风险也会变，
  新披露的 CVE 只有定时任务能发现）{% endif %}；{% if ci == 'github' %}
- CI 里的第三方 action 全部用 commit hash 钉死，并由 dependabot 每周更新；
- workflow 本身由 [zizmor](https://docs.zizmor.sh/) 做静态审计（脚本注入、过宽权限、缓存投毒）；{% endif %}{% if docker and crate_type == 'bin' %}
- 容器镜像基于 distroless，无 shell、无包管理器，以非 root 用户运行；{% endif %}
- 默认 `unsafe_code = "forbid"`，源码里出现 `unsafe` 直接编译失败。
