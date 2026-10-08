# 应用内自动更新

更新日期：2026-10-08。Sparkle 2.10.0 已接入维护源码；0.2.1 的公开发布仍暂停，现有公开附件保持原样。GitHub Pages 目前提供带签名的空清单，不向玩家提供未发布的本机测试包。

## 玩家使用

首次需要手动安装包含 Sparkle 的译芽版本，之后可在 macOS 顶部「译芽」菜单选择「检查更新…」。默认每天自动检查，有更新时由玩家选择安装；可取消「自动检查更新」。安装完成重新打开译芽，也可在更新提示中选择稍后安装。

更新替换应用包，设置、收藏、学习数据库和凭据继续位于玩家自己的应用数据目录。同一应用版本仅增加 build 时保留 API Key；应用版本号改变后重新填写一次，继续遵守 [本机凭据约定](api-key-storage.md)。Sparkle 更新验签仅使用应用内公钥；玩家启动和更新不需要读取维护者发布私钥。

## 维护者发布

固定清单地址为 <https://onecoffeecup.github.io/yiya-translator/appcast.xml>，来自本仓库 `gh-pages` 分支根目录。只向该分支发布 `appcast.xml` 和 `.nojekyll`，不发布整个源码或文档目录。应用更新附件来自 GitHub Releases 的具体标签地址。

1. 先完成目标版本的检查，保持公开发布的 build 单调递增。构建默认使用 Git 提交数；需要明确编号时可设置 `FY_BUILD_NUMBER`。同一应用版本可以使用 `v版本-build-编号` 标签发布后续修复，禁止用不同内容替换已公告的同一个 build。
2. 运行 `scripts/release-app.sh`。会生成带指南的首次安装包，以及只含 `.app` 的 `yiya-版本-build-编号-update.zip`；压缩后回验签名、UUID、资料和更新配置。
3. 准备更新清单，例如：

```bash
python3 scripts/prepare-update.py \
  --archive dist/release/yiya-0.2.1-build-13-update.zip \
  --tag v0.2.1 \
  --notes docs/发布说明.md
```

编号是示例，以本次构建输出为准。该命令核对应用身份、build、签名与公钥，从线上下载并验证已发布清单，随后使用 Sparkle 官方工具生成更新签名、清单及可用的差分包。只加入所选 build，并恢复线上历史条目的原始下载地址、说明和签名，避免生成工具用新标签改写旧地址；差分包只允许从已发布 build 升级，未公开的本地草稿不作为历史版本公告。产物在 `.build/update-publish/`，历史应用档案在 `dist/updates/archives/`。

4. 按原 [发布流程](发布流程.md) 完成正式应用附件与 Release。确认标签对应最终源码、Release 不再是草稿后运行：

```bash
python3 scripts/publish-update.py --site .build/update-publish
```

该命令上传独立更新附件，重新下载核对远端 SHA-256，最后发布已签名清单并触发 Pages。已有同名附件不会被覆盖；版本倒退、身份不匹配、签名失败或远端散列不符时停止发布清单。需保留 `dist/updates/archives/` 中的已发布旧应用，以便后续生成差分包；没有可用差分时使用完整更新包。

清单目前面向早期测试用户；GitHub Release 的 Pre-release 标记不会自动成为 Sparkle 的过滤条件。以后如需稳定版与测试版分流，应显式配置不同清单或频道。

## 发布私钥与依赖

锁定的下载地址、SHA-256、版本和公钥在 `resources/updates/sparkle-config.json`。普通构建自动下载并校验官方 Sparkle，缓存于 `~/Library/Caches/com.nanami.fuyi-build/`；应用包包含上游 framework、辅助程序和完整许可。构建无需发布私钥，也不需要 Swift 工程。

维护者的 Ed25519 私钥默认位于 `~/Library/Application Support/com.nanami.fuyi-publisher/updates/ed25519.key`，目录 `0700`、文件 `0600`。私钥是未加密的本机签名材料，必须单独保管、备份，不能进入 Git、源码包、应用包或更新附件。它与玩家的翻译 API Key 无关，不通过 Keychain 保存。

发布工具可通过 `FY_UPDATE_PRIVATE_KEY_FILE` 指定恢复的原私钥，用现有 OpenSSL 3 验证密钥匹配；必要时用 `FY_OPENSSL` 指定已有 OpenSSL 工具。普通玩家无需安装这些开发工具。公钥已配置后，`init-key` 不会生成或自动替换缺失的发布身份。

首次创建更新服务时使用 `prepare-update.py --bootstrap` 和 `publish-update.py --bootstrap`；重复执行会复用相同空清单，拒绝用新空清单覆盖已公告版本。当前 Pages 已完成初始化。

## 本轮验证

- 接入后的完整本机回归 55 步全部通过，其中 47 步实际运行原生界面／安装测试；没有跳过或仅编译步骤。包含语法动作、200 次工作区循环、OCR／贴译、采集卡、凭据和剪贴板恢复，详见 [最新发布检查记录](发布检查结果.md)。
- arm64 / x86_64 构建通过，仍有既有的 7 条未使用函数警告。
- 原生菜单、关闭／开启自动检查、空签名清单、真实 Sparkle 安装与重启、篡改清单拒绝、篡改更新包拒绝通过。临时测试应用使用独立 bundle ID、合成 API Key、设置和学习数据库，正常升级与失败后文件内容和权限保持不变。
- 原有凭据检查通过：18 条文件存储检查与 10 条设置检查；真实玩家凭据和学习数据库未用于测试。
- 更新分发检查覆盖错误身份／标签／build／公钥、关闭验签、凭据文件、重复路径、路径穿越、越界符号链接、macOS ZIP 中文文件名、跨标签历史地址保留及草稿差分过滤。发布安装包解压签名与内容回验、签名清单本地生成，以及线上空清单下载和验签通过。

```bash
python3 tests/UpdateDistributionTests.py
FY_TEST_ALLOW_UI=1 python3 scripts/run-update-tests.py
```

运行真实安装测试前预留桌面；测试与 `run-acceptance.py` 共用预留锁。`--compile-only` 或 `FY_TEST_COMPILE_ONLY=1` 仅编译，不记录为安装测试通过。这两项已加入常规检查与验收入口。

接入专项证据在本机 `.build/sparkle-download/` 与 `.build/update-checks/summary.json`，最新完整回归记录在 `.build/acceptance/20261008T000530Z-5aca7b/summary.json`。原采集卡失败的单帧夹具已按生产两帧确认规则修正，专项和完整回归均通过；生产代码未改。此轮未替换运行中的玩家应用，也未创建 0.2.1 Release。实际普通玩家下载升级、跨机器、Intel 实机与屏幕录制／相机权限继承仍待现场验收。

官方参考：[接入](https://sparkle-project.org/documentation/)、[程序入口](https://sparkle-project.org/documentation/programmatic-setup/)、[发布与签名](https://sparkle-project.org/documentation/publishing/)。
