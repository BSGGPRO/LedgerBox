import Foundation
import SwiftUI

/// A visual probe for the local finance-intent model.
///
/// The map is an intent-activation view, not a literal neuron scan. Every
/// number and bar comes from the local hashed classifier in `FinanceMind`.
struct FinanceBrainMapView: View {
    @Environment(\.ledgerTheme) private var theme

    @State private var query = "这个月现金流怎么样？"
    @State private var probe: FinanceBrainProbe? = FinanceMind.shared.probe(
        "这个月现金流怎么样？"
    )
    @State private var hasAppeared = false
    @State private var autoDemo = true
    @State private var demoIndex = 0
    @FocusState private var queryFocused: Bool

    private let demoQueries = [
        "这个月现金流怎么样？",
        "预算还剩多少？",
        "报销怎么记？",
        "固定资产折旧怎么算？",
        "客户欠款怎么催？",
        "怎么存钱才不月光？",
        "增值税进项税怎么抵扣？",
        "房贷月供怎么记？",
        "今天怎样避免乱花钱？",
        "目标还要多久才能达成？"
    ]

    private var intents: [FinanceIntent] {
        FinanceIntent.allCases
    }

    var body: some View {
        VStack(spacing: theme.spacing) {
            brainOrb
            modelStats
            probeCard
            coverageCard
            disclaimer
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) {
                hasAppeared = true
            }
            if probe == nil {
                runProbe()
            }
        }
        .onChange(of: queryFocused) { _, focused in
            if focused {
                autoDemo = false
            }
        }
        .onReceive(
            Timer.publish(every: 4.4, on: .main, in: .common).autoconnect()
        ) { _ in
            guard autoDemo, !queryFocused else {
                return
            }
            demoIndex = (demoIndex + 1) % demoQueries.count
            let next = demoQueries[demoIndex]
            withAnimation(.easeInOut(duration: 0.55)) {
                query = next
                probe = FinanceMind.shared.probe(next)
            }
        }
    }

    // MARK: - Orb

    private var brainOrb: some View {
        LedgerCard {
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("本地财务大脑")
                            .font(theme.sectionTitleFont)
                            .foregroundStyle(theme.primaryText)

                        Text("40 类记账意图 · 纯本地推理")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                    }

                    Spacer()

                    Label("离线", systemImage: "lock.fill")
                        .font(theme.badgeFont)
                        .foregroundStyle(theme.income)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.income.opacity(0.12), in: Capsule())
                }

                ZStack {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        BrainOrbCanvas(
                            predictions: probe?.predictions ?? [],
                            phase: timeline.date.timeIntervalSinceReferenceDate
                        )
                    }
                    .frame(height: 286)
                    .scaleEffect(hasAppeared ? 1 : 0.94)
                    .opacity(hasAppeared ? 1 : 0)

                    VStack(spacing: 3) {
                        Text(millions)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.primaryText)

                        Text("参数")
                            .font(theme.badgeFont)
                            .foregroundStyle(theme.secondaryText)

                        Text("Int8 · 本地")
                            .font(theme.badgeFont)
                            .foregroundStyle(theme.accent)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    Image(systemName: autoDemo ? "waveform.path.ecg" : "pause.circle")
                        .font(theme.badgeFont)
                        .foregroundStyle(autoDemo ? theme.accent : theme.secondaryText)

                    Text(query)
                        .font(theme.badgeFont)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Button {
                        autoDemo.toggle()
                        if autoDemo {
                            runProbe()
                        }
                    } label: {
                        Text(autoDemo ? "暂停巡演" : "自动巡演")
                            .font(theme.badgeFont)
                            .foregroundStyle(autoDemo ? theme.accent : theme.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(theme.surfaceElevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var millions: String {
        String(format: "%.2fM", Double(FinanceMind.parameterCount) / 1_000_000)
    }

    // MARK: - Stats

    private var modelStats: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("模型体检")
                    .font(theme.sectionTitleFont)
                    .foregroundStyle(theme.primaryText)

                HStack(spacing: 8) {
                    statTile("参数", value: "20,971,560", note: "40 × 524,288 + 40")
                    statTile("意图", value: "40", note: "记账 / 会计 / 理财")
                }

                HStack(spacing: 8) {
                    statTile("哈希桶", value: "524,288", note: "字符 1–3 gram")
                    statTile("体积", value: "10.0 MB", note: "Int8 权重 + Float bias")
                }

                HStack(spacing: 6) {
                    Image(systemName: "memorychip")
                    Text(FinanceMind.shared.isReady ? "模型已加载" : "模型资源缺失")
                    Spacer()
                    Text("不调用网络")
                }
                .font(theme.badgeFont)
                .foregroundStyle(
                    FinanceMind.shared.isReady ? theme.secondaryText : theme.expense
                )
            }
        }
    }

    private func statTile(_ title: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(theme.badgeFont)
                .foregroundStyle(theme.secondaryText)

            Text(value)
                .font(theme.rowMoneyFont)
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(note)
                .font(theme.badgeFont)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .padding(10)
        .background(
            theme.surfaceElevated,
            in: RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous)
        )
    }

    // MARK: - Probe

    private var probeCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("实时探针")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)

                    Spacer()

                    if let probe {
                        Text(String(format: "%.2f ms", probe.latencyMilliseconds))
                            .font(theme.badgeFont)
                            .foregroundStyle(theme.income)
                    }
                }

                HStack(spacing: 8) {
                    TextField("输入一句财务问题", text: $query)
                        .font(theme.bodyFont)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($queryFocused)
                        .padding(10)
                        .background(
                            theme.surfaceElevated,
                            in: RoundedRectangle(
                                cornerRadius: theme.controlRadius,
                                style: .continuous
                            )
                        )
                        .onSubmit {
                            runProbe(manual: true)
                        }

                    Button("探测") {
                        runProbe(manual: true)
                    }
                    .font(theme.buttonLabelFont)
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(theme.accent, in: Capsule())
                    .buttonStyle(.plain)
                }

                if let probe {
                    HStack {
                        Text("激活 \(probe.featureCount) 个特征")
                        Spacer()
                        Text("\(probe.bucketCount.formatted()) 桶")
                    }
                    .font(theme.badgeFont)
                    .foregroundStyle(theme.secondaryText)

                    ForEach(Array(probe.predictions.prefix(6).enumerated()), id: \.offset) { index, prediction in
                        predictionRow(prediction, rank: index + 1)
                    }
                } else {
                    Text("模型没有返回结果。请确认 FinanceMindWeights.bin 已打进 App。")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.expense)
                }

                Text("探针显示的是意图分类概率，不是大模型生成的答案。")
                    .font(theme.badgeFont)
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    private func predictionRow(_ prediction: FinanceIntentPrediction, rank: Int) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Text("\(rank)")
                    .font(theme.badgeFont)
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 14)

                Text(prediction.intent.displayName)
                    .font(theme.bodyFont.weight(rank == 1 ? .semibold : .regular))
                    .foregroundStyle(theme.primaryText)

                Spacer()

                Text("\(prediction.percent)%")
                    .font(theme.rowMoneyFont)
                    .foregroundStyle(rank == 1 ? theme.accent : theme.secondaryText)
            }

            ProgressView(value: Double(prediction.confidence))
                .tint(rank == 1 ? theme.accent : theme.secondaryText.opacity(0.55))
        }
    }

    private func runProbe(manual: Bool = false) {
        if manual {
            autoDemo = false
        }
        withAnimation(.easeInOut(duration: 0.45)) {
            probe = FinanceMind.shared.probe(query)
        }
    }

    // MARK: - Coverage

    private var coverageCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("训练覆盖")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)

                    Spacer()

                    Text("\(intents.count) 类")
                        .font(theme.badgeFont)
                        .foregroundStyle(theme.accent)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    ForEach(intents, id: \.self) { intent in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(
                                    probe?.predictions.first?.intent == intent
                                        ? theme.accent
                                        : theme.secondaryText.opacity(0.45)
                                )
                                .frame(width: 5, height: 5)

                            Text(intent.displayName)
                                .font(theme.badgeFont)
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                    }
                }

                Text("覆盖：收支、预算、储蓄、负债、退款、转账、保险、税务、现金流、对账、发票、报销、工资、存货、折旧、摊销、增值税、权责发生、备用金、应收应付、借款、房贷、房租、水电、医疗、教育、公益。")
                    .font(theme.badgeFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var disclaimer: some View {
        Text("这是任务专用分类器，不是生成式大模型；训练数据为合成语料，真实场景仍需你自己验证。")
            .font(theme.badgeFont)
            .foregroundStyle(theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}

private struct BrainOrbCanvas: View {
    @Environment(\.ledgerTheme) private var theme
    let predictions: [FinanceIntentPrediction]
    let phase: TimeInterval

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxRadius = min(size.width, size.height) * 0.46
            let breath = 1 + 0.045 * sin(phase * 1.6)
            let rotation = phase * 0.075

            // Soft breathing halo behind the rings.
            let haloRadius = maxRadius * 1.04 * CGFloat(breath)
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - haloRadius,
                    y: center.y - haloRadius,
                    width: haloRadius * 2,
                    height: haloRadius * 2
                )),
                with: .radialGradient(
                    Gradient(colors: [
                        theme.accent.opacity(0.10),
                        theme.accent.opacity(0.015),
                        .clear
                    ]),
                    center: center,
                    startRadius: 4,
                    endRadius: haloRadius
                )
            )

            let ringFractions: [CGFloat] = [0.46, 0.70, 0.94]
            for (ringIndex, fraction) in ringFractions.enumerated() {
                let radius = maxRadius * fraction
                let rect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(theme.separator.opacity(0.55)),
                    style: StrokeStyle(
                        lineWidth: 1,
                        dash: [3, 9],
                        dashPhase: CGFloat(phase * 20 + Double(ringIndex) * 6)
                    )
                )
            }

            let intents = FinanceIntent.allCases
            var points: [CGPoint] = []
            for (index, intent) in intents.enumerated() {
                let baseAngle = (Double(index) / Double(intents.count)) * 2 * Double.pi
                    - Double.pi / 2
                let angle = baseAngle + rotation
                let ring: CGFloat = index.isMultiple(of: 2) ? 0.88 : 0.67
                let radius = maxRadius * ring
                let point = CGPoint(
                    x: center.x + CGFloat(cos(angle)) * radius,
                    y: center.y + CGFloat(sin(angle)) * radius
                )
                points.append(point)

                let activation = predictions.first { $0.intent == intent }?.confidence ?? 0
                let isTop = predictions.first?.intent == intent
                let pulse = 0.86 + 0.14 * sin(phase * 2.3 + Double(index) * 0.73)
                let baseDot: CGFloat = isTop ? 5.5 : (2.2 + CGFloat(activation) * 4)
                let dotRadius = baseDot * CGFloat(pulse)

                if isTop {
                    let halo = dotRadius + 6 + CGFloat(sin(phase * 3) * 2)
                    let haloRect = CGRect(
                        x: point.x - halo,
                        y: point.y - halo,
                        width: halo * 2,
                        height: halo * 2
                    )
                    context.fill(
                        Path(ellipseIn: haloRect),
                        with: .color(theme.accent.opacity(0.14))
                    )
                }

                let rect = CGRect(
                    x: point.x - dotRadius,
                    y: point.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                let color: Color = isTop
                    ? theme.accent
                    : (activation > 0.08 ? theme.income : theme.secondaryText.opacity(0.35))
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }

            for (index, prediction) in predictions.prefix(5).enumerated() {
                guard let intentIndex = intents.firstIndex(of: prediction.intent) else {
                    continue
                }
                let point = points[intentIndex]
                var line = Path()
                line.move(to: center)
                line.addLine(to: point)
                context.stroke(
                    line,
                    with: .color(
                        theme.accent.opacity(0.42 - Double(index) * 0.06)
                    ),
                    lineWidth: index == 0 ? 1.8 : 1
                )

                // A pulse travels from the core to each active intent, so the
                // map moves even when the user is not typing.
                let raw = phase * 0.48 + Double(index) * 0.17
                let progress = CGFloat(raw - floor(raw))
                let particle = CGPoint(
                    x: center.x + (point.x - center.x) * progress,
                    y: center.y + (point.y - center.y) * progress
                )
                let particleRadius: CGFloat = index == 0 ? 2.4 : 1.7
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: particle.x - particleRadius,
                        y: particle.y - particleRadius,
                        width: particleRadius * 2,
                        height: particleRadius * 2
                    )),
                    with: .color(theme.accent.opacity(0.72 - Double(index) * 0.09))
                )
            }

            let coreRadius = 38 * CGFloat(breath)
            let core = CGRect(
                x: center.x - coreRadius,
                y: center.y - coreRadius,
                width: coreRadius * 2,
                height: coreRadius * 2
            )
            context.fill(
                Path(ellipseIn: core),
                with: .radialGradient(
                    Gradient(colors: [
                        theme.accent.opacity(0.36),
                        theme.accent.opacity(0.05)
                    ]),
                    center: center,
                    startRadius: 2,
                    endRadius: coreRadius + 6
                )
            )
            context.stroke(
                Path(ellipseIn: core),
                with: .color(theme.accent.opacity(0.34)),
                lineWidth: 1
            )

            let orbitRadius = coreRadius + 7
            let orbitAngle = phase * 0.9
            let orbitPoint = CGPoint(
                x: center.x + CGFloat(cos(orbitAngle)) * orbitRadius,
                y: center.y + CGFloat(sin(orbitAngle)) * orbitRadius
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: orbitPoint.x - 2,
                    y: orbitPoint.y - 2,
                    width: 4,
                    height: 4
                )),
                with: .color(theme.accent.opacity(0.8))
            )
        }
    }
}
