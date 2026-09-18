# CI 构建与 macOS 签名证书配置

仓库包含两个 GitHub Actions 工作流：

| 工作流 | 文件 | 触发 | 作用 |
| --- | --- | --- | --- |
| CI | `.github/workflows/ci.yml` | push / PR 到 `main`、`develop` | debug 构建 + 全量单测 + ad-hoc 打包冒烟 |
| Release | `.github/workflows/release.yml` | 推送 `v*` tag 或手动触发 | 导入证书 → release 构建 + 正式签名 → （可选）公证 → zip 上传 + GitHub Release |

`develop` 为日常开发分支，`main` 保持可发布状态；发版时从 `main` 打 `v*` tag。

## Release 所需 Secrets

在 **Settings → Secrets and variables → Actions → New repository secret** 逐个添加：

### 必填（正式签名）

| Secret | 内容 |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | 证书（含私钥）导出的 `.p12` 文件整体 base64 编码后的字符串 |
| `MACOS_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `SIGNING_IDENTITY` | 证书 Common Name，见下方获取方式 |
| `APPLE_TEAM_ID` | 10 位 Team ID（Apple Developer → Membership Details） |

### 可选

| Secret | 内容 |
| --- | --- |
| `KEYCHAIN_PASSWORD` | CI 临时钥匙串密码；不配置时每次运行自动随机生成 |
| `APPLE_ID` | 公证用 Apple ID（开发者账号邮箱） |
| `APPLE_APP_SPECIFIC_PASSWORD` | 公证用 App 专用密码（appleid.apple.com → 登录与安全 → App 专用密码） |

> 配齐 `APPLE_ID` + `APPLE_APP_SPECIFIC_PASSWORD` + `APPLE_TEAM_ID` 后，Release 构建会自动走 notarytool 公证 + stapler 装订；缺少任何一个则跳过公证。仅 `Apple Development` 证书（无 Developer ID）时公证会失败，此时建议用 `workflow_dispatch` 勾选"跳过公证"，或干脆不配公证 Secrets。

## 导出证书并生成 Secret 值

1. 打开 macOS **钥匙串访问**（Keychain Access），选择 **登录** 钥匙串 → **证书** 分类。
2. 右键目标证书（分发选 **Developer ID Application: ...**；内部测试可接受 **Apple Development: ...**）→ **导出…"**。
   - 格式选 **个人信息交换 (.p12)**，设置一个密码（即 `MACOS_CERTIFICATE_PASSWORD`）。
   - 导出时需同时勾选私钥（展开证书项，导出时钥匙串会连带私钥）。
3. base64 编码并复制到剪贴板（结果填入 `MACOS_CERTIFICATE_P12`）：

```sh
base64 -i certificate.p12 | pbcopy
```

## 获取 SIGNING_IDENTITY

```sh
security find-identity -v -p codesigning
```

输出形如：

```text
  1) 1234ABCD56 "Developer ID Application: Your Company (AB12CD34EF)"
```

引号内的完整字符串即 `SIGNING_IDENTITY`（例如 `Developer ID Application: Your Company (AB12CD34EF)`）。

## 触发一次签名发布

```sh
git switch main
git merge --no-ff develop        # 确认要发布的提交
git tag v0.6.1
git push origin main --tags      # push tag 触发 Release 工作流
```

构建产物会上传为 workflow artifact；tag 触发的构建同时创建 GitHub Release 并附带 `zappale-<version>.zip`。

## 降级行为

- 未配置任何签名 Secrets：Release 工作流给出 warning，退回 ad-hoc 签名（产物仅能本机冒烟，不可分发）。
- 配置了签名但未配齐公证 Secrets：正常签名打包，跳过公证。
- CI（测试）工作流永不使用证书，始终 ad-hoc 冒烟。

## 本地验证签名（可选）

```sh
./scripts/build-app.sh                     # ad-hoc（默认）
SIGN_IDENTITY="Developer ID Application: Your Company (AB12CD34EF)" \
APPLE_TEAM_ID="AB12CD34EF" \
./scripts/build-app.sh                     # 正式签名 + hardened runtime
codesign verify --strict --verbose=2 build/zappale.app
```
