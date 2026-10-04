# 拼音 LocalPinyinLab

自用 macOS 双语输入法实验项目，使用 Swift、AppKit 和 InputMethodKit。提供中文拼音与英文直出两种模式：中文模式在白色竖排候选框中同时显示中文候选及英文译文，蓝底白字标记当前选中项。

拼音候选来自本机 Apple CoreChineseEngine，翻译使用已安装的 Apple Translation 中英模型，英文朗读使用 Apple 本地英语声音。项目不包含第三方拼音词库、云端翻译服务或自行编写的词条翻译表。

> 拼音部分依赖苹果私有 API，目前仅在开发机 macOS 27.0.1 上验证。使用苹果引擎不代表与系统“简体拼音”的候选、排序、学习和上下文行为完全一致；系统升级也可能使接口失效。当前版本适合个人实验，尚未完成多应用兼容性验收。

## 功能与实际行为

- **中文输入**：支持整句候选、前缀候选、逐段选词、撤回已选片段，以及每页最多 9 项的候选翻页。
- **英文直出**：Caps Lock 在拼音内部切换中英模式，不显示中文候选。英文默认小写，Shift 输入大写；普通按键交给宿主处理，必要时仅纠正 Caps Lock 对 ASCII 字母大小写的影响。
- **双语候选**：中文候选先显示，当前页译文异步补充；翻译未完成不阻塞中文选词。
- **英文朗读**：按 `Control + Shift + R` 朗读蓝色选中项已显示的英文译文，不提交中文，也不修改当前拼音。
- **回车保留拼音**：有组合文字时，Return / 数字键盘 Enter 提交当前组合并关闭候选，不附加换行；没有组合时由宿主正常处理回车。
- **首键响应优化**：预热并复用拼音 worker，查询在独立队列执行；过期查询与翻译不会覆盖新一轮输入。
- **单实例保护**：正常输入服务在注册 IMK 连接前取得进程锁，避免系统自动启动与手动启动同时创建服务。

### 翻译的对象是什么？

输入、翻译和朗读按以下顺序处理：

```text
拼音 nihao
  → 苹果拼音引擎生成候选「你好」「你号」等
  → 分别把候选中文发送给 Apple Translation
  → 显示「你好  Hello」「你号  Your account」等译文
  → Control + Shift + R 朗读当前选中行的英文
```

译文示例来自此前验证，具体输出可能随系统模型变化。实现见 [InputSession.swift](Sources/PinyinApplication/InputSession.swift) 与 [AppleTranslator.swift](Sources/PinyinInfrastructure/AppleTranslator.swift)。

翻译输入是**每一行候选的中文内容**，不是原始拼音。逐段选词时，译文对应当前候选片段；翻译请求不额外携带文档前文或已经选好的中文片段。候选列表会过滤表情（包括含表情的混合候选），保留普通文字、数字和标点。含汉字的候选才请求翻译，纯拼音候选不请求翻译。

**保留 Apple Translation 的原始译文。** 此前尝试的“自动挑选单一译法”、`白字 → Miswritten character` / `期 → Period` 等改写已撤销。因此译文可能包含 `or`、多个含义或音译；本项目不保证孤立词条的译法符合某个特定语境，也不在客户端拆分或替换译文。

### 与系统简体拼音的区别

本项目独立调用 `CoreChineseEngine.framework` 中的 `CIMMecabraEngine`，没有接管或复用系统简体拼音的完整输入会话。worker 禁用词频学习，不接入联系人、个人词库或附加词库，并在每次查询前后重置组合状态。

开始一轮输入时，输入控制器会尝试读取光标前最多 128 个 UTF-16 单位的文字；后续查询结合已选中文片段，仍限制在该长度内。宿主不支持读取时使用空上下文。这属于有限的前文辅助，不能等同于系统输入法的全部上下文能力。

此前实测 `pingying` 在本项目中首项为“平英”，系统简体拼音首项为“瓶赢”。现在可以先选择“瓶”，保留 `ying`，再选择“赢”，但**候选完整性、首项排序、个性化学习和原生功能全面一致仍未实现或验证**。无法映射到输入拼音前缀的引擎候选也会被过滤，以避免错误消耗拼音。

## 环境要求

| 项目 | 要求 / 已验证环境 |
| --- | --- |
| 架构 | Apple Silicon（arm64）；脚本未提供 Intel 或通用二进制构建 |
| 部署目标 | 主程序声明 macOS 26.0+；不代表所有这些系统版本均已验证 |
| 开发机 | macOS 27.0.1（26A434），arm64 |
| 工具链 | 已验证 Apple Swift 6.4、macOS 27.0 SDK、Xcode Command Line Tools |
| 翻译 | 已安装的简体中文 → 英语 Apple Translation 模型 |
| 朗读 | 至少一个已安装的 Apple 英语声音 |
| 脚本工具 | Bash、Python 3、`xcrun`、`codesign`、`sandbox-exec` |

使用较新 SDK 构建：源码含 macOS 26.4+ 的 `.lowLatency` 翻译策略分支，旧 SDK 不一定能够编译。当前使用 [Swift Package](Package.swift) 声明模块及编译依赖，启用 Swift 6 语言模式；无需 Xcode 工程或第三方包。构建和测试脚本共用 SwiftPM 配置。

[Info.plist](Info.plist) 当前版本为 `0.1.0`，构建号 `16`。程序仅做本机 ad-hoc 签名，没有 Developer ID 签名或公证。

## 构建与翻译模型准备

以下命令均在仓库根目录执行：

```sh
bash Scripts/build.sh
```

主产物为 `build/LocalPinyin.app`。构建工具使用 AppKit / CoreText 系统字体生成圆角底牌与镂空“中英”文字模板，导出为 22×16 pt、普通 / Retina 两档 TIFF。文字处真正透明，由背景透出；macOS 为底牌着色，使其适配浅色菜单、深色菜单栏和选中状态。菜单图标与 Control + 空格切换时的光标提示共用此模板，光标提示也会显示带底牌的“中英”。图标生成不依赖私有框架或苹果图像资源。脚本同时生成翻译探针、输入源诊断工具和候选 UI 预览工具，对 worker 与应用签名并验证。**构建不会安装、注册、启用或切换输入源。**

首次使用翻译前，可以构建并打开独立的模型准备工具：

```sh
bash Scripts/build-translation-setup.sh
open build/TranslationSetup.app
```

按照苹果系统提示准备中英文离线模型。首次准备可能需要下载；下载由用户在系统提示中确认。该工具只测试“你好、谢谢、学习”等固定合成文本。正常输入法只使用已安装模型，不自动触发模型下载。

检查模型状态和真实翻译：

```sh
build/translation-probe
```

缺少模型时，探针会显示 `SKIP`，这不表示翻译测试通过。输入法中的中文候选仍可使用，英文栏会显示“未安装中英离线语言包”。

## 安装、更新与卸载

### 首次安装

1. 构建完成后，将 `build/LocalPinyin.app` 复制到当前用户的 `~/Library/Input Methods/`。目录不存在时创建它，保留原有系统输入源。
2. 在“系统设置 → 键盘 → 文字输入 → 编辑”中点击 `＋`，从“简体中文”添加“拼音”，点击“完成”。英文系统下名称为 `Pinyin`。
3. 在 TextEdit 等测试应用中，从菜单栏选择“拼音”，确认能保持选中，再输入合成文本 `nihao`，检查候选与空格上屏。

如果新安装的输入法尚未出现在添加列表中，可先保存文稿，再从苹果菜单退出当前 **macOS 用户会话**并重新登录。无需退出 Apple 账户或 iCloud。此前本机排障中，重新登录后还需要在文字输入设置里手动移除并重新添加“拼音”，才能保存为可选输入源。

### 更新已安装版本

1. 保留旧应用备份，先结束当前组合并切换到系统输入源。
2. 退出旧的 `LocalPinyin` 输入服务，再替换 `~/Library/Input Methods/LocalPinyin.app`，避免运行中的旧版本继续占用输入连接。
3. 让系统重新启动该服务并选回“拼音”；如需手动启动，只启动安装目录中的副本。
4. 用合成文本重新检查候选、删除、选词和朗读。若宿主仍保留失效会话，保存文稿后重开宿主；必要时重新登录用户会话。

名称或图标更新后，`TextInputMenuAgent`、`CursorUIViewService` 和 `TextInputSwitcher` 可能仍保留旧缓存，即使 TIS 接口已返回新内容。刷新相应 UI 进程后，应同时检查实际输入菜单和空白文本框中的切换提示，不能只依据注册工具的输出。

不要同时从构建目录和安装目录启动正常输入服务。单实例锁会拒绝后启动的实例，因此只覆盖文件或启动成功并不能证明运行进程已经换成新版本。也不要通过删除仍被持有的锁文件来强制启动第二个实例。

### 卸载

切换到系统输入源，在文字输入设置中移除“拼音”，退出其进程，再删除安装目录中的 `LocalPinyin.app`。保留或删除源码不会影响其他输入法。上述流程不需要关闭 SIP、Gatekeeper 或系统隐私保护。

## 键盘操作

| 按键 | 行为 |
| --- | --- |
| 小写 `a`–`z`、`'` | 输入拼音；一轮组合的原始拼音总长度最多 128 个字符 |
| 空格 | 选择蓝色高亮项；部分候选仅转换前缀，剩余拼音继续选词 |
| `1`–`9` | 选择当前页对应候选 |
| `↑` / `↓` | 移动高亮，跨越页边界时随之翻页 |
| Page Up / Page Down | 切换候选页，选中该页首项 |
| `←` | 撤回最近一次已选片段，恢复该片段的原始拼音 |
| Backspace | 删除待转换拼音末字符；没有待转换拼音时尝试撤回上一片段 |
| Esc | 取消当前组合，关闭候选 |
| Return / 数字键盘 Enter | 提交当前可见组合，不额外插入换行 |
| `Control + Shift + R` | 朗读当前选中项已就绪的英文译文，不上屏 |
| Caps Lock | 在拼音内部切换中文 / 英文；切换前提交当前组合，英文默认小写，Shift 大写 |
| `Control + Shift + Space` | 切换中文拼音 / 英文直出；切换前提交尚未结束的组合 |

例如：`nihao` 尚未选词时按回车，上屏 `nihao`；`pingying` 已选“瓶”而剩余 `ying` 时按回车，上屏 `瓶ying`。没有组合时，回车和删除键交给宿主应用。

本地输入服务内各控制器共享中英模式，切换应用时保留，服务重启后默认中文。激活时只同步 Caps Lock 按键基线，不把在其他输入法中发生的按键当成本地模式切换。Caps Lock 不再用于本地英文的大写锁定，输入大写请按住 Shift；其他输入源的大写规则由系统或对应输入法决定。目前没有独立模式指示器或设置界面。候选窗口仅支持键盘操作，鼠标点击选词尚未实现。

拼音只注册为中文输入源，不参与系统的 Caps Lock 拉丁输入源切换。macOS 的“使用大写锁定键切换输入法”是另一项系统功能：要阻止原生简体拼音也用该键切换到其他输入源，需要在系统键盘设置中关闭它。本项目不修改苹果输入法，也不宣称原生简体拼音具有与本地相同的小写英文内部模式。修改注册配置后可运行 `build/inputsource-tool --check-registration` 核实实际分类；仅替换 plist 或注册返回成功不能证明缓存已刷新。

输入法显式接收修饰键和鼠标按下事件。具有文档索引的鼠标回调在组合范围外提交；只有原始鼠标事件时，点击会提交当前组合，再交给宿主处理光标移动。

### 朗读规则

- 使用 `AVSpeechSynthesizer`，优先选择已安装的美式英语 Samantha，其次其他 Apple 美式英语声音，再其次其他 Apple 英语声音；排除个人声音和趣味声音。
- 朗读内容就是当前行显示的就绪英文译文。没有就绪译文时显示提示，不朗读拼音、加载提示或错误提示，也不会在翻译稍后完成时自动播放。
- 继续输入、移动候选、翻页、提交或停用输入服务会停止朗读。再次按快捷键会重新播放，长按的重复按键被忽略。
- 不使用麦克风，不录音，不自动下载声音；目前没有语速、音色选择界面。
- 原来的 `Option + Space` 朗读键已停用；`Command + Space` 没有被本项目绑定。当前快捷键按键码识别，其他键盘布局尚未全面验证。

## 源码结构与实现

项目按真实 Swift 模块拆分，模块导入与依赖由 [Package.swift](Package.swift) 检查。完整的状态约束、时序、扩展步骤见 [架构说明](Docs/ARCHITECTURE.md)。

```text
Sources/
  PinyinCore/           组合、拼音规则、候选、分页、翻译状态值
  PinyinApplication/    输入会话协调、服务端口、批量翻译与缓存
  PinyinInfrastructure/ 苹果服务、worker 通信、输入源及单实例锁
  PinyinPresentation/   AppKit 候选窗口、绘制、快照和按键适配
  LocalPinyin/          IMK 宿主适配、服务装配、主入口和演示
  TestSupport/          仅供测试的轻量断言，无需 XCTest
Worker/                正式运行的苹果拼音 worker 与沙盒
Probes/                模型准备与独立诊断工具
Tests/                 独立模块测试和真实系统集成测试
Scripts/               统一构建与测试入口
Resources/             中英文输入源名称
```

| 模块 | 职责与边界 | 项目内依赖 |
| --- | --- | --- |
| `PinyinCore` | 纯值类型和同步规则；状态通过受控操作修改 | 无，仅 Foundation |
| `PinyinApplication` | 按键行为、宿主生命周期、查询与翻译请求有效期、缓存；通过协议调用外部能力 | Core |
| `PinyinInfrastructure` | 本地引擎进程、Apple Translation、AVSpeech、TIS 和进程锁 | Core、Application |
| `PinyinPresentation` | 只渲染当前页快照，适配 NSEvent；不负责选词或发起查询 | Core、Application |
| `LocalPinyin` | 装配真实服务，衔接 IMK 生命周期与宿主 marked text | 以上四个模块 |

核心业务可以从 [CompositionState](Sources/PinyinCore/CompositionState.swift)、[CandidateList](Sources/PinyinCore/CandidateList.swift) 和 [InputSession](Sources/PinyinApplication/InputSession.swift) 独立阅读。系统能力的接口集中在 [Ports.swift](Sources/PinyinApplication/Ports.swift)，输入会话不导入 AppKit、InputMethodKit、Translation 或 AVFAudio。

主要约束：

- 拼音只能由小写 ASCII 字母和 `'` 组成；已选片段的原始拼音加待转换后缀总长不超过 128。选择必须消费有效的非空前缀，撤回恢复原始分隔符。
- 候选只存引擎文本和消费长度；展示和选词前统一过滤表情，译文使用独立状态枚举，成功译文、加载状态、模型缺失与错误不会混用。朗读只接受成功且非空的汉字候选译文。
- 分页只存一个绝对选中索引，页号与页内高亮由它推导；空列表没有选中项，每页最多 9 项。
- 输入查询与页翻译各有独立请求标识。输入变化、翻页、取消、提交和停用会使旧请求失效；即使服务忽略取消，迟到响应也无法更新当前状态。
- 翻译响应必须完整、标识唯一、与请求一一对应。整批验证后才更新最多 256 项的内存 FIFO 缓存；每个请求保留自己的缓存命中快照，避免并发淘汰导致崩溃。

正常输入使用预热的常驻 worker；独立演示及部分测试每次新建一个 worker，并复用同一套安全传输。管道读取每次有 3 秒期限，通信失败后最多重启重试一次；非法拼音在启动进程前拒绝。响应帧最多 4 MiB，输入与上下文只走匿名管道。取消会跳过尚未执行的旧请求，已经执行的请求返回后丢弃结果；进程退出或无响应时清理本项目创建的子进程。

翻译只处理当前页含汉字的候选，去重后批量请求，按标识恢复原顺序。macOS 26.4+ 选择低延迟策略；不自动下载模型，不改写真实译文。

## 测试与诊断

先执行 `bash Scripts/build.sh`，再按需要运行：

| 命令 | 验证范围 |
| --- | --- |
| `bash Scripts/check-core.sh` | 纯状态约束、翻译缓存与响应完整性、输入会话异步竞态、worker 协议和 AppKit 事件映射；不需要词库、语言包或声音 |
| `bash Scripts/check-synthetic.sh` | 真实苹果引擎的短词、长句、分隔符、前缀候选，以及逐段选择、撤回、删除和上下文长度 |
| `build/translation-probe` | 模型状态、固定中文样本的真实翻译、缓存重复项和结果顺序 |
| `bash Scripts/check-speech.sh` | 快捷键与高亮行映射、拒绝未就绪内容、本地语音合成为内存 PCM；不经扬声器播放 |
| `bash Scripts/check-single-instance.sh` | 跨进程互斥及释放后重新取得锁 |
| `bash Scripts/check-return-key.sh` | 真实 InputSession 配合协议测试替身，验证回车、组合前缀、无组合透传、宿主重入及迟到响应；另测 NSEvent 映射 |
| `bash Scripts/check-performance.sh` | 常驻 / 单次查询对比、上下文重置、快速输入取消、子进程崩溃恢复及超时清理 |

测试使用合成输入，不注册输入源或修改安装中的应用。语音与翻译测试依赖本机资源；私有引擎测试包含具体候选断言，系统升级导致输出变化时需要检查失败原因。回车测试直接注入宿主、查询和窗口协议，不再通过改写源文件或伪造 IMK 类进行测试；它不能替代真实应用中的键盘验收。测试是 SwiftPM 可执行目标，使用轻量断言，不依赖完整 Xcode 的 XCTest；统一入口为 `bash Scripts/check-core.sh`，不是 `swift test`。

只读诊断示例：

```sh
build/LocalPinyin.app/Contents/MacOS/LocalPinyin --runtime-check
build/LocalPinyin.app/Contents/MacOS/LocalPinyin --source-status
build/inputsource-tool
```

`--runtime-check` 检查控制器类名及 bundle 标识；`--source-status` / 无参数的 `inputsource-tool` 读取输入源状态。TIS 返回已启用、已选中或状态码 0，不能证明某个应用中的实际输入正常。

`--register` 以及 `inputsource-tool` 的 `register`、`enable`、`select-test`、`restore-original` 参数会修改输入源状态，不是只读诊断，也不作为常规安装步骤；其中 `restore-original` 实际选择的是固定的系统简体拼音标识，并非动态恢复任意先前输入源。

不安装输入法也可以查看固定样本：

```sh
# 真实引擎候选；有模型时附带真实翻译。演示窗口不处理选词按键。
build/LocalPinyin.app/Contents/MacOS/LocalPinyin --demo --long-sample
# 导出 pingying 的候选图，不注册正常输入服务。
build/LocalPinyin.app/Contents/MacOS/LocalPinyin --snapshot build/candidates.png --candidate-sample
# 手写合成 UI 数据，仅用于布局预览，不是苹果引擎或翻译输出。
build/candidate-preview build/candidate-preview-synthetic.png
```

## 已验证结果与待验证项

### 显示名称更新（2026-10-04，构建 16）

- 中文显示名称由“中英拼音”改为“拼音”，英文名称改为 `Pinyin`；保留现有 bundle 和输入源标识。
- 图标内容、圆角镂空样式及 `TISIconLabels.Primary` 仍为“中英”，安装后的 TIFF 与构建 14 逐字节一致。
- 已安装到当前电脑并刷新系统 UI 缓存；实际展开菜单及收起的菜单栏均已确认显示“拼音”和原来的“中英”图标。
- 安装包严格签名、运行时标识及非 ASCII 注册约束检查通过，系统 Caps Lock 切源开关仍为关闭。以下按构建号保留历史名称与调查记录。

### 圆角镂空图标更新（2026-10-04，构建 14）

- 将“中英”图标改为圆角底牌和透明字形，保留普通 / Retina 两档模板，文字通过 alpha 镂空而非固定白色绘制。
- 已安装并刷新系统 UI 缓存；实际截图确认浅色展开菜单中为黑底白字，收起到当前蓝色菜单栏时为白底、字形透出背景。
- 图标与光标旁的切换提示仍然共用，本次统一为带底牌的“中英”；输入法完整名称仍是“中英拼音”。
- 模板尺寸、字形透明度、安装签名和非 ASCII 登记约束检查通过，Caps Lock 相关实现未改动。

### 原生菜单与光标图标分流调查（2026-10-04）

目标是菜单显示圆角镂空“中英”，文本框内 Control + 空格的系统切换提示使用不带底牌的“中英”（未选中白底黑字、选中蓝底白字）。**构建 14 尚未同时满足这两个要求**。

本机 macOS 27.0.1（26A434）的只读运行时检查和实际切换试验得到以下结果；这些是当前系统的实现观察，不是苹果公开的兼容性保证：

- 原生简体拼音由 `KeyboardLayouts.framework` 的 `KLInputSourceIconManager` 分别生成菜单图像和 `indicatorImageForInputSource:` 图像。内置 `KLDynamicInputSourceIconTable` 实际为含 291 个 Apple 输入源条目的常量字典，本地输入源不在其中；未找到添加第三方条目的入口。
- 第三方菜单与现代光标提示都读取当前 Hans 输入源的 `TSMInputSourcePropertyIconImage`。光标提示把 22×16 pt 图像居中放入 30×23 pt 画布；Retina 图像裁出的内容与菜单模板 alpha 完全相同，额外尺寸的图片不能按这两个场景分流。
- `TISIconLabels.Primary` 可供其他切换界面读取，但没有改变本机现代光标提示的图像来源；分开 Menu / Alternate / Palette 文件也不能替代这一路径。
- 光标提示的 `inputMode` 来自系统当前输入源 ID，经过 `tsmSourceIndicatorSourceIDKey` 传入 `TUIInputModeAccessory`；该路径没有调用 IMK 的独立图标或标签回调。
- 按 [Inputx 的历史调查线索](https://github.com/goliajp/inputx/blob/714d41b1ab24bf2fb122dce82ed0814e194f52b2/docs/macos-ime-recipe-2026.md#gate-35--cfbundleiconname-makes-ctrlspace-switcher-read-your-app-icns-instead-of-menu-tiff)，临时安装保留菜单底牌、另设 `CFBundleIconName` / `CFBundleIconFile` 纯文字多分辨率 `.icns` 的实验包。空白 `NSTextView` 中实际切换到本地输入源后，光标提示仍显示原来的底牌，未实现分流。

实验包已撤回，安装恢复为构建 14；全部 bundle 文件哈希与试验前备份一致，严格签名及非 ASCII 注册检查通过，系统 Caps Lock 切源开关仍为关闭。现阶段可以分别画出两种样式，但尚未找到让系统在这两处独立使用它们的有效接入口，不能将此次调查标记为 UI 修复完成。

### 中英切换标识更新（2026-10-04，构建 13）

- 菜单图标与光标旁切换提示统一为“中英”文字，输入法完整名称仍为“中英拼音”。图标生成仅使用 AppKit，不再读取系统私有图像资源。
- 在当前 macOS 上，现代光标提示直接复用第三方输入源图像；`TISIconLabels.Primary` 本身不能独立更改这个提示。保留该标签供其他系统切换界面使用。
- 已安装并刷新系统 UI 缓存；独立空白 `NSTextView` 内实际触发 Control + 空格，截图确认“中英”显示于系统蓝色胶囊中，按住 Control 时的输入源列表也显示“中英”。与简体拼音对比，胶囊外形和选中效果由同一个系统界面呈现。
- 1× / 2× 模板尺寸、安装包严格签名、运行时标识与输入源注册检查通过；Caps Lock 相关代码和非 ASCII 登记约束保持原状。

### 名称与菜单图标更新（2026-10-04，构建 11）

- 已安装到当前电脑，中文名称为“中英拼音”，英文名称为 `Chinese-English Pinyin`；保留原有 bundle 和输入源标识。
- 菜单使用系统生成的圆角“拼”字模板；父输入法和 Hans 模式分别声明 `TISIconIsTemplate`，让普通与高亮状态由系统着色。
- 刷新 `TextInputMenuAgent` 后，已通过实际菜单文字和截图确认名称、普通图标及蓝色选中效果；不能仅用 TIS 返回的新名称判断菜单缓存已经更新。
- release 构建、安装包严格签名检查、控制器运行时检查和输入源注册约束检查通过；根输入源与 Hans 模式仍为非 ASCII 输入源，系统 Caps Lock 切源开关保持关闭。

### Caps Lock 更新（2026-10-04，构建 5）

- 本地输入源只声明中文，明确不参与系统 Caps Lock 切源；已安装版本经 TIS 实际检查，根输入源及中文模式的 `ASCIICapable` 均为 false，当前 ASCII 输入源为 British。
- 新增 Caps Lock 内部模式切换、跨控制器模式共享及 ASCII 大小写处理；保留组合提交、快捷键和安全输入边界，并补充鼠标提交及宿主重入保护。
- `check-core.sh`、更新后的 `check-return-key.sh`、release 构建和安装包严格签名检查通过。测试覆盖重复修饰键、漏收修饰键后的普通按键补同步、Shift、快捷键混用、迟到结果与重入时的新组合保留。
- 已备份旧版本后更新当前电脑的输入服务，并关闭系统 Caps Lock 切源开关。该开关的修改仅是本机安装操作，不是输入服务启动时的行为。
- 用户实体按键验收：中英拼音按 Caps Lock 后 `abc` 输出小写，`Shift+A` 输出大写 A，再按 Caps Lock 输入 `nihao` 恢复中文候选；原生简体拼音按 Caps Lock 后 `abc` 也输出小写。同步输入源记录确认按键期间分别保持中英拼音和原生简体拼音。此结果限定当前电脑、当前系统与本次测试宿主，不代替所有应用或系统版本的兼容性验证。

### 本次重构验证（2026-10-04）

- Swift 6 release 构建、worker 与应用的严格签名检查、控制器运行时名称/bundle 标识检查均通过。
- `check-core.sh` 通过：13 组核心约束、15 组翻译服务、7 组 worker 协议测试，以及输入会话和 NSEvent 映射回归。
- 真实引擎的短词、整句、前缀、逐段选择、撤回和删除通过；翻译模型状态为 installed，实际中英翻译与缓存顺序通过。
- 本地 Samantha 语音向内存生成 50,360 个 PCM 帧；跨进程锁排他与释放、worker 崩溃恢复、取消和超时回收均通过。
- 合成 UI 预览和真实 `pingying` 候选 PNG 已导出检查，保持白色竖排与蓝色高亮。模型准备工具仅完成构建，未打开或触发下载。
- 本次常驻 `p` / `n` / `nihao` 查询中位耗时分别为 1.35 / 1.36 / 3.33 ms；独立查询约 114.50 / 116.90 / 121.99 ms。模拟无响应 worker 在 7.10 秒内完成重试与强制回收。

本次未安装或替换当前输入服务。上述结果验证代码、协议、系统服务与构建产物；重构后的真实 IMK 宿主键盘行为仍需实机验收。部分首次 SwiftPM 链接输出了 CLT 缺少 Xcode 专用搜索目录的警告，但构建、链接、运行及签名检查均成功。

### 重构前的实机与历史记录

以下保留此前开发对话的记录，不能代替重构版本或其他机器的验收。

| 项目 | 结果与边界 |
| --- | --- |
| TextEdit 短词 | 用户确认 `nihao` 显示中文与英文，空格上屏“你好” |
| TextEdit 长句 | 用户确认 `xianzaibeijingshijianjidianzhong` 显示“现在北京时间几点钟”及译文，空格可上屏 |
| 逐段选词 | 用户确认 `pingying` 可先选“瓶”，再从 `ying` 选“赢”，最终上屏“瓶赢” |
| 首键速度 | 常驻 worker 优化后用户反馈明显更快，选词和上屏正常 |
| 删除与候选恢复 | 重启服务后，用户确认 TextEdit 候选出现、删除正常 |
| 新朗读快捷键 | 用户确认 TextEdit 中 `Control + Shift + R` 听到 Hello，候选正常，未把“你好”上屏 |
| 构建与合成测试 | 已有记录中构建、严格签名、候选、分段、翻译、语音、单实例和故障恢复检查通过 |
| 回车 | 旧版本曾安装并通过内存宿主测试；重构版本的协议回归测试结果见上方，真实应用中的实体键盘行为仍待确认 |
| 英文模式切换 | 代码已实现；用户曾暂缓专门验收，不能据此标记完整通过 |
| Codex 与其他宿主 | Codex 曾发生输入会话故障，恢复后尚无单独确认；多应用、全屏、多屏和不同键盘布局仍待覆盖 |

此前本机性能测量中，`p` / `n` / `nihao` 的单次启动查询约 116–123 ms，常驻查询约 1.8–3.8 ms。这是拼音查询耗时，**不包含完整的按键、UI 绘制、翻译和显示链路**，不是跨机器性能承诺。

## 排障与已知限制

**候选缺失或无法切换输入源**：先确认菜单栏实际选中“拼音”。如果只有字母正常直出，可能处于英文模式，可用模式快捷键切回；如果连输入或删除都无响应，应先切回系统输入源恢复编辑，再按更新流程重启本地服务及受影响宿主。

曾出现其他软件可用，但 TextEdit / Codex 中候选、输入或删除无响应的情况。后续一次更新中观察到两个服务进程，已加入单实例保护；但这不足以证明原始故障只有这一个根因。服务启动成功、进程存活或 worker 查询成功都不能替代宿主实测。

其他限制：

- 私有 API 与 `sandbox-exec` 都存在系统版本兼容风险；引擎不可用时显示状态，不切换为第三方词库冒充苹果候选。
- 未实现系统输入法的完整学习、模糊拼音设置、标点策略、组合内任意光标编辑或全部原生快捷键。
- 译文为独立候选的机器翻译，不是完整词典释义、词性或经过人工校对的单一译法。
- 候选窗口固定白色，不跟随深色外观；长译文暂不换行或截断，可能超出窄屏可用宽度。
- 光标位置由宿主 IMK 接口提供；取不到位置时回退到鼠标位置，不保证所有输入框定位一致。

## 数据与隐私边界

- 正常输入的拼音、有限前文和候选通过匿名管道在本机进程间传递，不放入命令行参数，不由项目写入键入日志或历史文件。
- **沙盒限制适用于拼音 worker**：允许读取配置中的系统资源及 worker 文件，不允许读取个人 Library、写入学习数据、联网或连接 XPC 服务。主输入服务及苹果 Translation / 语音服务不在这个 worker 沙盒内。
- 主输入控制器通过公开 IMK 接口按需读取有限前文；提交或停用后清除组合及前文。启用安全输入时放弃处理按键。
- 翻译缓存仅保存在控制器内存中，最多 256 条；不因每次提交立即清空，在淘汰或缓存服务释放后移除。项目不持久保存该缓存。
- 正常服务仅输出固定生命周期诊断信息；命令行探针可以输出它们自身的合成样本。单实例锁文件位于 `~/Library/Caches/local.pinyinlab.inputmethod/input-service.lock`，不保存输入内容。
- 仓库排除编译应用、构建缓存、运行日志、安装备份和个人测试文稿。苹果词库、翻译模型及声音由系统提供，不随源码分发。

## 许可与来源

本项目采用 **GPL-3.0-or-later**，见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。候选窗口布局与定位参考 [qingjian-team/qingjian](https://github.com/qingjian-team/qingjian) 的 AppKit 实现，使用独立 Swift 实现并按本项目需求调整白色外观和双语行。

参考版本为 `c08ae57cb88b6a4a46f4a5e9c1d6d11c5e69222e`，阅读的上游文件包括 `apps/macos/src/candidates/theme.rs`、`view/mod.rs`、`view/matrix.rs`、`window.rs` 以及 `apps/macos/Info.plist`。具体归属见 NOTICE。项目没有使用青简名称 / logo 素材，也没有分发其词库或苹果词库与模型。
