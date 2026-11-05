# AyuGram 隐藏视频控件 —— 改动与编译记录

## 1. 功能改动（已完成，已生成补丁）

补丁文件：`feature-hide-video-controls.patch`（本目录）

改动内容：

| 文件 | 作用 |
| --- | --- |
| `Telegram/SourceFiles/ayu/ayu_settings.h/.cpp` | 新增设置项 `hideVideoControlsWhilePlaying`（默认关闭），随 AyuGram 设置 JSON 持久化 |
| `Telegram/Resources/langs/lang.strings` | 新增两个文案 key：`ayu_HideVideoControlsWhilePlaying` / `ayu_HideVideoControlsWhilePlayingDescription` |
| `Telegram/SourceFiles/ayu/ui/settings/settings_general.cpp` | AyuGram 设置 → General 里新增开关 + 说明文字 |
| `Telegram/SourceFiles/media/view/media_view_overlay_widget.h/.cpp` | 开关打开时，视频播放中鼠标移动不再唤出控制条/标题；点击、按键、打开菜单仍可正常唤出（1.1s 后自动隐藏） |

行为细节：
- 只在“视频正在播放”时抑制鼠标悬停唤出（`Media::Streaming::Player` 未暂停、未结束）。
- 暂停状态下鼠标移动仍会显示控件，方便拖动进度。
- 位于 `activateControls(bool fromMouseMove)` 的入口判断，见 `media_view_overlay_widget.cpp` 里 `shouldHideVideoControls()`。

编译环境相关的临时改动（**不属于功能补丁**，只影响本机依赖构建）保存在
`C:\tbuild\build-workarounds.patch`。

## 2. 编译进度（未完成）

构建目录：`C:\tbuild\tdesktop`（本仓库副本，源码改动已同步），依赖目录
`C:\tbuild\Libraries\win64`、`C:\tbuild\ThirdParty`。

已安装：
- Visual Studio 2022 Build Tools 17.14.44（MSVC 14.44.35207 + Windows SDK 10.0.26100）
- CMake / Ninja（随 Build Tools 组件）

已构建完成（Debug + Release 两套）：
zlib、mozjpeg、openssl3、opus、rnnoise、dav1d、openh264、libavif、libde265、
libwebp、libheif、libjxl、libvpx、liblcms2、ffmpeg、openal-soft

未完成：
- `breakpad`（chromium.googlesource.com 被墙，需换 GitHub 镜像 `google/breakpad`
  的 tarball，并把 `google/googletest` release-1.11.0 放到 `src/testing`）
- `tg_angle`（GitHub clone）
- `qt_5.15.19`（Qt5 静态构建，最耗时的一步；qtbase/qtimageformats/qtsvg 源码
  可从 codeload 的 tarball 拉，见下方技巧）
- `tg_owt`（WebRTC，含大量 submodule）
- `ada`、`tde2e`、`tlottie`（Rust/cargo）
- 之后才是 `configure` + `cmake --build out --config Debug --target Telegram`

## 3. 编译结果

**已编译成功（Debug）**

- 产物：`C:\tbuild\tdesktop\out\Debug\AyuGram.exe`（494 MB，7.2.9.0）
- 已复制一份到本目录：`dist\AyuGram.exe`
- 冒烟测试：能正常启动（进程存活，占用约 242MB）

完整日志：
- 依赖：`C:\tbuild\prep_18.log`（EXIT=0）
- 配置：`C:\tbuild\configure.log`（EXIT=0）
- 编译：`C:\tbuild\build.log`（EXIT=0）

使用：打开 AyuGram → Settings → AyuGram → General → 打开
“Hide Player Controls While Playing”，播放视频时鼠标划过画面不会再弹出
控制条/标题；点击或按键仍可临时唤出。

## 3b. Release 版（正式版）进度

**Debug 版已发布；Release 版正在编译。**

阻塞原因：当初为省时间把 Qt 的 `-debug-and-release` 改成 `-debug`，
`C:\tbuild\Libraries\win64\Qt-5.15.19\lib` 里只有 `Qt5Cored.lib`，
Release 配置要找 `Qt5Core.lib`（无 d 后缀），直接 configure 会失败。

已完成（2026-11-05）：

- `C:\tbuild\qt_release.bat`：用 `-debug-and-release` 重新 configure Qt，
  `jom`/`jom install` 生成并安装 Release 库，`qt_release.log` 结尾 `EXIT=0`
- 坑：脚本 PATH 里加了 `msys64\usr\bin`，导致 `link` 被 GNU coreutils 的
  `link` 抢走（`: extra operand '/NXCOMPAT'`）；去掉后解决
- `C:\tbuild\release_pipeline.ps1`：等 Qt 装完 → 重新 configure →
  设 `ProcessorNumber` → `cmake --build out --config Release` →
  最多 20 次增量重试 → 冒烟测试 → 拷到 `dist\AyuGram-Release.exe`

Release 版用 Embedded 调试信息（/Z7），不需要 mspdbsrv，内存比 Debug 友好；
但这台机器 16GB + 后台 Chrome/微信仍会偶发 `C1060 编译器堆空间不足`，
所以并行度从 4 降到 2/1，靠 pipeline 的增量重试补齐失败文件。

产物（编完后）：`C:\tbuild\tdesktop\out\Release\AyuGram.exe`
预计 40–70 MB（对比 Debug 的 494 MB）。

**最终结果（2026-11-05 21:31，已发布）**：
`AyuGram-7.2.9-release-x64.exe`，**228.1 MB**，sha256
`679c796f2b305d88850bd7bc7da628e676607d4616fbd1f7fe963204d2dfb02a`。

MSBuild 路线最终放弃（反复 `MSB4018`，tlog 从不提交 → 永远从头编），
**改用 Ninja 生成器成功**：

```bat
set "QT=5.15.19"
cmake -S . -B out-ninja -G "Ninja Multi-Config" ^
  -D TDESKTOP_API_ID=2040 -D TDESKTOP_API_HASH=b18441a1ff607e10a989891a5462e627 ^
  -D CMAKE_MSVC_DEBUG_INFORMATION_FORMAT=
cmake --build out-ninja --config Release --target Telegram -- -j3
:: 产物 C:\tbuild\tdesktop\out-ninja\Release\AyuGram.exe
```

关键：**Release 配置一定要去掉 `/Z7`（Embedded 调试信息）**。默认
`variables.cmake` 给非 Debug 配置设 `Embedded`，单个 obj 会到 100–160 MB、
cl 吃 7.8 GB，16GB 机器必然反复 OOM。configure 时传
`-D CMAKE_MSVC_DEBUG_INFORMATION_FORMAT=` 即可。

Ninja 的优点：每个 obj 是独立边，中断/崩溃都不丢进度（MSBuild 的 tlog 是
整个 CL 任务结束才写，一崩就全部白编）。

脚本：`C:\tbuild\ninja_configure.bat`、`C:\tbuild\run_ninja_build.bat`、
`C:\tbuild\ninja_pipeline.ps1`；日志 `C:\tbuild\ninja_build.log`。

> 注意：`ninja_pipeline.ps1` 里含中文目标路径，PowerShell 5.1 以 ANSI 读取
> UTF-8 无 BOM 脚本会乱码，导致最后一步 Copy-Item 到 `dist` 失败。编完后手动
> `Copy-Item -LiteralPath` 即可（或把脚本存成 UTF-8 BOM）。

日志：`C:\tbuild\release_pipeline.log`、`C:\tbuild\release_build.log`。

### 2026-11-05 下午：两个坑（已处理，重编中）

1. **`LNK1136 无效或损坏的 obj`**：pipeline 20 次重试都卡在
   `Telegram.dir\Release\data_peer.obj` —— 该文件是 0 字节（之前 cl 因
   内存不足写了一半）。MSBuild 的 tlog 认为它已构建，不会自动重编。
   处理：删掉 0 字节 obj。
   > 教训：批量扫描 obj 时不要用「COFF 头是 `64 86`」当判据！MSVC 的
   > `/Z7` / LTCG obj 开头其实是 `00 00 FF FF`。曾误判导致把 1075 个
   > Release obj 全删了，只能全量重编。**只删 0 字节文件即可。**
2. **`MSB4018 ToolOutputPipe` + C1060**：4 个 cl 在 16GB 机器上（还开着
   Chrome/微信）反复 OOM，且 MSBuild 会挂住不退出。
   处理：`release_pipeline.ps1` 改为并行度 4→2→1 递减、`Wait-Process
   -Timeout 5400` 防挂死、共 16 次增量重试（每次只补失败/缺失的 obj）。

`run_release_build.bat` 里的 `/m:N`、`/p:CL_MPCount=N` 和 vcxproj 里的
`<ProcessorNumber>N</ProcessorNumber>` 由 pipeline 自动设置，不要手工改。

## 4. 继续编译的方法

```bat
:: 1) 继续准备依赖（可重复执行，已完成的 stage 会跳过）
C:\tbuild\run_prepare6.bat        :: 结果在 C:\tbuild\prepare6.log，结尾出现 EXIT=0 即成功

:: 2) 配置
C:\tbuild\run_configure.bat       :: C:\tbuild\configure.log

:: 3) 编译
C:\tbuild\run_build.bat           :: C:\tbuild\build.log
:: 产物：C:\tbuild\tdesktop\out\Debug\AyuGram.exe
```

## 4. 本机网络环境下的踩坑记录

1. `Telegram/build/prepare/prepare.py` 里 msys2 包名 `mingw-w64-x86_64-diffutils`
   在新版 msys2 仓库里已不存在，改成 `diffutils`。
2. GitHub clone 经常卡死/限速，可用 `git config --global url."https://gh-proxy.com/https://github.com/".insteadOf "https://github.com/"`。
3. Rust 从 `static.rust-lang.org` 只有 ~40KB/s，设置
   `RUSTUP_DIST_SERVER=https://rsproxy.cn`、`RUSTUP_UPDATE_ROOT=https://rsproxy.cn/rustup`。
4. 大文件（rustc / 源码包）用 `curl -r` 分段并发下载再 `copy /b` 合并最快；
   GitHub 源码包走 `https://gh-proxy.com/https://codeload.github.com/...` 比 git 协议快得多。
5. Qt 只需 Debug：prepare.py 里 Qt stage 的 `SET CONFIGURATIONS=-debug-and-release`
   已改为 `-debug`（否则静态 Qt 的 Debug+Release 双份要编很久）。
6. `prepare.py` 中给已经手工准备好的源码目录建 `.preclone` 标记文件，脚本会自动
   跳过该 stage 的 `git clone / git checkout / git submodule` 行，避免重复下载。
