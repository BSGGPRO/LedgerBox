import Foundation

/// Local Qwen2.5-0.5B-Instruct narrator.
///
/// The model is intentionally *not* allowed to produce financial arithmetic.
/// It receives a deterministic `FinanceAdvice` that was already computed with
/// `Decimal`, and may only rewrite the prose. Any number in the rewrite that
/// is not present in the source text is rejected, so a hallucinated amount can
/// never reach the ledger UI.
@MainActor
final class QwenLocalModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case loading
        case ready(parameters: UInt64)
        case unavailable(String)
        case failed(String)

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }

        var summary: String {
            switch self {
            case .idle:
                return "尚未加载"
            case .loading:
                return "正在加载 0.5B…"
            case .ready(let parameters):
                return "已加载 · \(Self.parameterText(parameters))"
            case .unavailable(let reason):
                return reason
            case .failed(let reason):
                return reason
            }
        }

        private static func parameterText(_ value: UInt64) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            return (formatter.string(from: NSNumber(value: value)) ?? "\(value)") + " 参数"
        }
    }

    static let shared = QwenLocalModel()

    static let modelFileName = "Qwen2.5-0.5B-Instruct-Q4_K_M"
    static let modelFileExtension = "gguf"

    @Published private(set) var status: Status = .idle
    @Published private(set) var isGenerating = false
    @Published private(set) var completedGenerations = 0
    @Published private(set) var rejectedGenerations = 0
    @Published private(set) var lastNarration: String?
    @Published private(set) var lastFailure: String?
    @Published private(set) var lastRunAt: Date?

    private let queue = DispatchQueue(
        label: "com.example.ledgerbox.qwen",
        qos: .userInitiated
    )
    private var handle: OpaquePointer?
    private var prepared = false

    private init() {}

    var isReady: Bool {
        status.isReady
    }

    /// Loads the framework and GGUF once. Safe to call from `.task` on every
    /// appearance; repeated calls are ignored after the first attempt.
    func prepare() {
        guard !prepared else { return }
        prepared = true

        guard lb_llama_platform_supported() == 1 else {
            status = .unavailable("模拟器不加载 0.5B")
            return
        }

        guard let modelURL = Bundle.main.url(
            forResource: Self.modelFileName,
            withExtension: Self.modelFileExtension
        ) else {
            status = .unavailable("安装包未包含 0.5B 模型")
            return
        }

        guard let frameworksPath = Bundle.main.privateFrameworksPath else {
            status = .unavailable("找不到 Frameworks 目录")
            return
        }

        let frameworkURL = URL(fileURLWithPath: frameworksPath)
            .appendingPathComponent("llama.framework/llama")
        guard FileManager.default.fileExists(atPath: frameworkURL.path) else {
            status = .unavailable("安装包未包含 llama 运行时")
            return
        }

        status = .loading
        lastFailure = nil
        LedgerLog.shared.info("qwen_prepare")
        let frameworkPath = frameworkURL.path
        let modelPath = modelURL.path

        queue.async { [weak self] in
            var error = [CChar](repeating: 0, count: 512)
            let created: OpaquePointer? = frameworkPath.withCString { framework in
                modelPath.withCString { model in
                    error.withUnsafeMutableBufferPointer { buffer in
                        lb_llama_create(
                            framework,
                            model,
                            2048,
                            4,
                            buffer.baseAddress,
                            buffer.count
                        )
                    }
                }
            }

            guard let created else {
                let message = error.withUnsafeBufferPointer { buffer in
                    guard let base = buffer.baseAddress else { return "模型加载失败" }
                    return String(cString: base)
                }
                DispatchQueue.main.async {
                    let detail = message.isEmpty ? "模型加载失败" : message
                    self?.status = .failed(detail)
                    self?.lastFailure = detail
                    LedgerLog.shared.error("qwen_load_failed")
                }
                return
            }

            let parameters = lb_llama_parameter_count(created)
            DispatchQueue.main.async {
                self?.handle = created
                self?.status = .ready(parameters: parameters)
                self?.lastFailure = nil
                LedgerLog.shared.info("qwen_ready", detail: "params=\(parameters)")
            }
        }
    }

    /// Releases the model. Never destroys the C handle while a generation is in
    /// flight; the queue owns the handle until `narrate` returns.
    func unload() {
        guard !isGenerating, let handle else { return }
        self.handle = nil
        prepared = false
        status = .idle
        isGenerating = false
        lastFailure = nil
        queue.async {
            lb_llama_destroy(handle)
        }
    }

    /// A user-initiated retry after a missing model, missing framework, simulator,
    /// or load failure. The destroy/create calls stay ordered on the serial queue.
    func retryLoad() {
        guard !isGenerating else { return }
        if handle != nil {
            unload()
        }
        prepared = false
        status = .idle
        lastFailure = nil
        prepare()
    }

    /// Produces a short, number-preserving explanation of `advice`.
    /// Returns nil for unavailable models, failures, empty output, or output
    /// that introduces a number not present in the deterministic source.
    func narrate(question: String, advice: FinanceAdvice) async -> String? {
        guard let handle, status.isReady, !isGenerating else {
            if !status.isReady {
                lastFailure = status.summary
            }
            return nil
        }
        isGenerating = true
        lastFailure = nil
        defer { isGenerating = false }

        let source = [
            question,
            advice.title,
            advice.body,
            advice.calculation?.formula ?? "",
            advice.calculation?.kind.displayName ?? ""
        ].joined(separator: "\n")

        let prompt = Self.prompt(question: question, advice: advice)

        return await withCheckedContinuation { continuation in
            queue.async {
                var output = [CChar](repeating: 0, count: 4096)
                var error = [CChar](repeating: 0, count: 512)

                let result = prompt.withCString { promptPointer in
                    output.withUnsafeMutableBufferPointer { outputBuffer in
                        error.withUnsafeMutableBufferPointer { errorBuffer in
                            lb_llama_generate(
                                handle,
                                promptPointer,
                                96,
                                0.10,
                                outputBuffer.baseAddress,
                                outputBuffer.count,
                                errorBuffer.baseAddress,
                                errorBuffer.count
                            )
                        }
                    }
                }

                guard result == 0 else {
                    LedgerLog.shared.error("qwen_generate_failed")
                    DispatchQueue.main.async {
                        self?.rejectedGenerations += 1
                        self?.lastFailure = "llama 生成失败"
                        self?.lastRunAt = Date()
                    }
                    continuation.resume(returning: nil)
                    return
                }

                let raw = output.withUnsafeBufferPointer { buffer in
                    guard let base = buffer.baseAddress else { return "" }
                    return String(cString: base)
                }
                let cleaned = Self.sanitize(raw)
                guard !cleaned.isEmpty,
                      Self.numbers(in: cleaned).isSubset(of: Self.numbers(in: source)) else {
                    LedgerLog.shared.warning("qwen_narration_rejected")
                    DispatchQueue.main.async {
                        self?.rejectedGenerations += 1
                        self?.lastFailure = "解释没有通过数字校验，已回退"
                        self?.lastRunAt = Date()
                    }
                    continuation.resume(returning: nil)
                    return
                }
                LedgerLog.shared.info("qwen_narration_ok", detail: "chars=\(cleaned.count)")
                DispatchQueue.main.async {
                    self?.completedGenerations += 1
                    self?.lastNarration = cleaned
                    self?.lastFailure = nil
                    self?.lastRunAt = Date()
                }
                continuation.resume(returning: cleaned)
            }
        }
    }

    private static func prompt(question: String, advice: FinanceAdvice) -> String {
        let formula = advice.calculation?.formula ?? "无"
        return """
        <|im_start|>system
        你是 LedgerBox 的本地账本解释器，不是计算器。
        只把下面已经算好的结果改写成 2 到 3 句简洁中文。
        规则：
        1. 不得新增、修改、计算任何金额、比例、日期或天数。
        2. 只能使用“已计算结果”里出现的数字；没有的数字就说“没有数据”。
        3. 不承诺收益，不构成投资、税务或法律建议。
        4. 只输出正文，不要标题、不要 Markdown、不要引号、不要解释规则。
        <|im_end|>
        <|im_start|>user
        用户问题：\(question)
        计算结果标题：\(advice.title)
        计算结果正文：\(advice.body)
        精算公式：\(formula)
        <|im_end|>
        <|im_start|>assistant
        """
    }

    private static func sanitize(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = text.range(of: "<|im_end|>") {
            text = String(text[..<range.lowerBound])
        }
        if text.count > 500 {
            text = String(text.prefix(500))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func numbers(in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(
            pattern: #"[0-9]+(?:[.,][0-9]+)?"#
        ) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return String(text[matchRange]).replacingOccurrences(of: ",", with: "")
        })
    }
}
