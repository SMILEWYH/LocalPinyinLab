# 构建与本地翻译准备

需要 Apple Silicon Mac、macOS 26 或更高版本，以及支持本项目 API 的 Swift 6 SDK。

## 构建

在项目根目录运行：

```sh
bash Scripts/build.sh
```

默认产物：

```text
~/Library/Caches/LocalPinyinLab/build/LocalPinyin.app
~/Library/Caches/LocalPinyinLab/build/inputsource-tool
```

产物和 SwiftPM 缓存放在本机缓存目录，避免 Desktop/iCloud 文件提供器给签名包添加 Finder 元数据。可以用 `LOCALPINYIN_BUILD_ROOT` 指定其他非同步目录，路径必须是绝对路径；使用 `CONFIGURATION=debug` 切换构建配置。脚本先验证新包，再整体替换旧产物，失败或收到可处理的中断信号时恢复旧包。

构建只生成产物，不会替换已安装的输入法、注册或切换输入源。使用新版功能前，应将完整的 `LocalPinyin.app` 更新到用户的 `~/Library/Input Methods/`，不能只替换其中的可执行文件。重新登录后，再从系统输入法菜单选择“拼音”。现有用户的显示名称和“中英”图标保持不变。

## 准备离线语言包

已安装新版输入法时，从系统输入法菜单选择 **中英离线语言包…**。工具会先检查是否已安装；如果未安装，点击 **准备语言包**，按 Apple 系统提示完成准备。准备工具可能需要网络，日常翻译只使用已安装的本地语言包。

窗口会显示检查中、尚未安装、准备中、已就绪或失败状态。完成后可关闭窗口直接继续输入；失败可重试，也可重新检查状态。准备语言包期间，中文输入仍可使用。

也可以单独构建并打开准备工具：

```sh
bash Scripts/build-translation-setup.sh
open "$HOME/Library/Caches/LocalPinyinLab/build/TranslationSetup.app"
```

如果设置了 `LOCALPINYIN_BUILD_ROOT`，请打开脚本最后输出的应用路径。应用包内也包含同一个工具，放在 `Contents/Resources/TranslationSetup.app`。

## 回归验证

```sh
bash Scripts/check.sh
```

- `input-checks`：标点、模式、大写锁定、分页、组合编辑和异步响应隔离。
- `worker-checks`：在临时目录运行假 worker，覆盖取消、超时、失败重试和子进程回收；不更改系统输入源。
- `presentation-checks`：窗口尺寸、长文本布局、候选序号与辅助功能语义。

这些检查不等于真实宿主验收。更新已安装的输入法后，还应在常用编辑器、浏览器和多屏环境验证候选定位、翻页、模式提示，并使用 VoiceOver 检查候选及译文。界面检查可通过 `presentation-checks --render-directory <绝对目录>` 导出离屏预览图片；导出图仅用于布局检查。
