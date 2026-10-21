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
            hasAppeared = true
            if probe == nil {
                runProbe()
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
                    BrainOrbCanvas(predictions: probe?.predictions ?? [])
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
                    statTile("参数", value: "10,485,800", note: "40 × 262,144 + 40")
                    statTile("意图", value: "40", note: "记账 / 会计 / 理财")
                }

                HStack(spacing: 8) {
                    statTile("哈希桶", value: "262,144", note: "字符 1–3 gram")
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        .padding(10)
                        .background(
                            theme.surfaceElevated,
                            in: RoundedRectangle(
                                cornerRadius: theme.controlRadius,
                                style: .continuous
                            )
                        )
                        .onSubmit(runProbe)

                    Button("探测", action: runProbe)
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

    private func runProbe() {
        withAnimation(.snappy) {
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

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxRadius = min(size.width, size.height) * 0.46

            for fraction in [0.46, 0.70, 0.94] {
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
                    lineWidth: 1
                )
            }

            let intents = FinanceIntent.allCases
            var points: [CGPoint] = []
            for (index, intent) in intents.enumerated() {
                let angle = (Double(index) / Double(intents.count)) * 2 * Double.pi
                    - Double.pi / 2
                let ring: CGFloat = index.isMultiple(of: 2) ? 0.88 : 0.67
                let radius = maxRadius * ring
                let point = CGPoint(
                    x: center.x + CGFloat(cos(angle)) * radius,
                    y: center.y + CGFloat(sin(angle)) * radius
                )
                points.append(point)

                let activation = predictions.first { $0.intent == intent }?.confidence ?? 0
                let isTop = predictions.first?.intent == intent
                let dotRadius: CGFloat = isTop ? 5.5 : (2.2 + CGFloat(activation) * 4)
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
            }

            let core = CGRect(
                x: center.x - 38,
                y: center.y - 38,
                width: 76,
                height: 76
            )
            context.fill(
                Path(ellipseIn: core),
                with: .radialGradient(
                    Gradient(colors: [
                        theme.accent.opacity(0.32),
                        theme.accent.opacity(0.04)
                    ]),
                    center: center,
                    startRadius: 2,
                    endRadius: 44
                )
            )
            context.stroke(
                Path(ellipseIn: core),
                with: .color(theme.accent.opacity(0.30)),
                lineWidth: 1
            )
        }
    }
}
