import AppKit
import InputMethodKit

// 仅验证公开 IMK 子类可编译。没有 IMKServer 实例、输入源注册或键盘监听。
@objc(LocalPinyinController)
final class LocalPinyinController: IMKInputController {
    var mode: InputMode = .englishDirect

    override func inputText(_ string: String!, client sender: Any!) -> Bool {
        // 引擎未确认前不消费任何输入；false 保留宿主直出行为。
        false
    }
}
