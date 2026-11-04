# 上游更新后，如何同步并保留这两个功能

适用对象：fork `gtzh/AyuGramDesktop`，功能分支 `feat/hide-video-controls`
（两个提交：`7dd9168` 隐藏控件、`d3e9cd5` 下载加速）。

## 0. 结论先行

用 **rebase，不要 merge**：把你的两个提交像补丁一样重新贴到上游最新代码上。

```
upstream/dev  ──●──●──● (上游新提交)
                     \
                      ●──●  你的 2 个提交 (rebase 之后)
```

不要用 GitHub 网页的 **"Sync fork"** 按钮了事 —— 它只更新 fork 的 `dev`，
不会动你的功能分支；也不要 `git merge upstream/dev`，那会产生 merge commit，
以后每次同步都会越滚越乱。

## 1. 一次性准备（已经帮你做过了）

```powershell
git remote add upstream https://github.com/AyuGram/AyuGramDesktop.git
git config rerere.enabled true        # 记住冲突怎么解的，下次自动复用
git config pull.rebase true
git config rebase.autoStash true
```

当前 remote：

```
origin    gh-proxy 加速的上游镜像（只读）
upstream  官方上游（走全局 insteadOf，实际也走 gh-proxy 加速）
mine      git@github.com:gtzh/AyuGramDesktop.git   ← 你的 fork
```

> ⚠️ **重要**：当初是 `--depth 1` 浅克隆，`.git/shallow` 存在。
> 浅仓库缺 merge-base，rebase 会出错或悄悄做错事。脚本第一次运行会自动执行
> `git fetch --unshallow upstream`（只做一次，要拉全历史，可能十几分钟）。
> 也可以现在手动跑：`git fetch --unshallow upstream --tags`

## 2. 以后每次上游更新，跑这一条

```powershell
cd C:\Users\Administrator\Documents\2026work\其他\test\ayu
powershell -File tools\sync-upstream.ps1              # 只看差多少（dry run）
powershell -File tools\sync-upstream.ps1 -Apply       # 备份 + rebase
powershell -File tools\sync-upstream.ps1 -Apply -Push # 顺便推到你的 fork
```

脚本做的事：

1. 检查工作区干净（`dist/`、`BUILD-NOTES-zh.md` 这类未跟踪文件不影响）
2. `git fetch upstream --tags`，浅仓库自动 unshallow
3. 打印「落后 N 个提交 / 你的 2 个提交」
4. `-Apply` 时先建备份分支 `backup/feat/hide-video-controls-YYYYMMDD-HHmm`
5. `git rebase upstream/dev`
6. `-Push` 时用 **`git push --force-with-lease`**（rebase 改写了历史，必须带 lease 的强推）
7. 顺带把 fork 的 `dev` 快进到上游

`-Apply` 不加 `-Push` 时只改本地，方便你先重新编译验证。

## 3. 冲突了怎么办

因为改的是**上游已有文件**（不是新增独立文件），上游动到同样的地方就会冲突。
按文件对照处理：

| 文件 | 我加的东西 | 冲突处理 |
| --- | --- | --- |
| `ayu/ayu_settings.h/.cpp` | 2 个 getter/setter/producer/member；`to_json` / `from_json` 各 2 行 | **两边都留**：上游新增的设置项 + 我的 `hideVideoControlsWhilePlaying` / `boostDownloadSpeed` |
| `ayu/ui/settings/settings_general.cpp` | `BuildQoLToggles` 里 2 个 `addSettingToggle` 块 + 说明文字 | 把我这 2 个块重新插到 `disableNotificationsDelay` 那个 toggle 之后 |
| `Resources/langs/lang.strings` | 4 行 `ayu_*` 文案 | 保留我的 4 行；上游新增行也保留 |
| `media/view/media_view_overlay_widget.h/.cpp` | `activateControls(bool fromMouseMove = false)`、`shouldHideVideoControls()`、事件过滤器里 `type == QEvent::MouseMove` | 上游若重构播放器，手工把这三处重新套上 |
| `storage/download_manager_mtproto.cpp` | 4 个常量改成函数：`startWaitedInSession()` / `maxWaitedInSession()` / `startSessionsCount()` / `maxSessionsCount()` | 上游若改常量名或数值，按新名字调整这几个函数 |

解决后：

```powershell
git add <冲突文件>
git rebase --continue
powershell -File tools\sync-upstream.ps1 -Apply -Push
```

`rerere` 会记住这次怎么解的；以后上游同样位置再改，git 会自动复用解决方案。

搞砸了随时回退：

```powershell
git rebase --abort
git reset --hard backup/feat/hide-video-controls-<时间戳>
```

## 4. 兜底：用补丁重新套

如果 rebase 冲突太乱，或者你换了台机器/重新 fork，直接从 Release 下载
`ayugram-custom-features.patch`（或本地 `git diff 0f2a31b HEAD` 生成），
在**全新上游代码**上三路合并：

```powershell
git checkout -b feat/hide-video-controls upstream/dev
git apply --3way ayugram-custom-features.patch
# 或者保留提交信息：
git am -3 <(git format-patch --stdout 0f2a31b..d3e9cd5)
```

生成补丁：

```powershell
git diff 0f2a31b HEAD -- Telegram/SourceFiles Telegram/Resources > ayugram-custom-features.patch
```

## 5. 同步完别忘了重新编译

`lang.strings` 或任何头文件变了都会触发大范围重编（这台机器约 3–5 小时）：

```bat
C:\tbuild\run_build.bat
:: 产物 C:\tbuild\tdesktop\out\Debug\AyuGram.exe
```

注意：编译前**关掉正在运行的 AyuGram.exe**，否则链接会报
`LNK1104 无法打开 AyuGram.exe`（这次就踩过）。

## 6. 常见误区

- ❌ 点网页 "Sync fork" 就以为功能分支也更新了 —— 不会。
- ❌ `git pull upstream dev` 在功能分支上直接合并 —— 产生 merge commit，历史污染。
- ❌ 强推用 `git push -f` —— 用 `--force-with-lease`，避免覆盖别人（或你在别处）的提交。
- ❌ 在 `dev` 分支上做这两个功能 —— 已经在独立分支了，保持这样。
- ❌ 浅克隆不 unshallow 就 rebase —— 会失败。
