# 本地拼音 LocalPinyinLab

自用 macOS 输入法实验项目，使用 Swift、AppKit 和 InputMethodKit。中文拼音候选来自本机 Apple CoreChineseEngine，英文译文来自已安装的 Apple Translation 模型；不包含第三方拼音词库或云端翻译服务。

## 当前状态

- 白底候选框，蓝底白字高亮，中文候选与英文译文同行显示。
- 支持整句拼音、前缀候选、逐段选词与撤回；候选排序不保证与系统拼音相同。
- 常驻沙盒 worker 预热，当前页异步翻译，过期响应丢弃，有界内存缓存。
- Option+Space 使用已安装的 Apple 英语声音朗读当前高亮项的英文译文。
- **已撤销单一译法筛选**：完整保留 Apple Translation 的原始译文，包括必要的 `or`。
- **源码包含回车直接提交拼音的改动，但尚未部署至本机输入法，也尚未实体验收。** 当前已安装程序恢复至该改动之前的备份版本；用户此前报告更新后候选框无法唤醒，恢复后的实际表现仍待确认。本仓库不将该问题标记为已解决。

## 构建

需要 Apple Silicon Mac、macOS 26+ 和 Xcode Command Line Tools。开发环境使用 Swift 6.4、macOS 27 SDK；Apple 私有拼音接口仅在开发机 macOS 27.0.1 上验证过。

```sh
bash Scripts/build.sh
bash Scripts/check-synthetic.sh
bash Scripts/check-speech.sh
# 可选：性能、取消与故障恢复检查
bash Scripts/check-performance.sh
```

构建产物在 `build/LocalPinyin.app`，脚本不自动安装或注册输入源。部分检查要求本机已安装苹果中英翻译模型或英语声音。

准备苹果离线翻译模型：

```sh
bash Scripts/build-translation-setup.sh
open build/TranslationSetup.app
```

模型下载由用户在系统提示中确认。运行 `build/translation-probe` 可检查已安装状态及固定合成词句的真实翻译。正常输入法不会主动下载模型。

## 源码键位

| 按键 | 行为 |
| --- | --- |
| 空格 | 选用蓝色高亮候选 |
| 回车 / 数字键盘 Enter | 上屏当前组合文字并关闭候选，不额外换行；未选词时保留拼音，逐段选择后保留已选中文和剩余拼音 |
| 1–9 | 选择当前页候选 |
| 上下键 | 移动高亮 |
| PageUp / PageDown | 翻页 |
| 左键 | 撤回最近一次分段选择 |
| Backspace / Esc | 删除 / 取消组合 |
| Option+Space | 朗读当前候选的就绪英文译文，不提交文字 |
| Control+Shift+Space | 中文拼音与英文直出切换 |

没有组合时回车交给宿主处理。朗读在更换候选、翻页、继续输入、提交或停用时停止。没有就绪译文时不朗读状态标签或原始拼音。英文直出切换、朗读实际出声及回车的新行为仍需实体键盘验收。

## 安装与限制

将构建的应用复制到当前用户的 `~/Library/Input Methods/`，再通过系统设置的键盘/文字输入界面添加“本地拼音”。保留原有系统输入源。修改已安装程序前自行保留备份；应用覆盖后可能需要切换输入源或重新登录。构建和进程启动成功不能代替实际宿主输入测试。

拼音接口属于苹果私有 API，系统升级可能导致不兼容。worker 仅允许读取必要系统资源，不读取个人词库或联系人，不写学习数据，不联网。上下文仅在内存中有界处理，提交或失焦后清除。没有持久键入记录。当前项目仍为实验版本，不承诺原生排序一致性、多宿主兼容性或稳定性；无需关闭 SIP、Gatekeeper 或隐私保护。

本仓库包含源码、合成测试及构建资源，不包含本机运行日志、安装备份、个人测试文稿、缓存或已编译应用。

## 许可与来源

候选窗口的布局参考 [qingjian](https://github.com/qingjian-team/qingjian)，遵循 GPL-3.0-or-later，详见 [LICENSE](LICENSE) 和 [NOTICE](NOTICE)。未使用青简名称/logo，也未分发其词库。
