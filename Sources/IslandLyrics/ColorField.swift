import SwiftUI
import AppKit

/// 方形色块按钮，点击弹出自定义中文取色器（HEX 输入 + RGB/不透明度滑杆 + 预设）。
struct ColorField: View {
    @Binding var color: Color
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)
                .frame(width: 42, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.primary.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .onHover { h in if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            ColorEditor(color: $color).frame(width: 250)
        }
    }
}

private struct ColorEditor: View {
    @Binding var color: Color
    @State private var hexText = ""

    private let presets: [Color] = [
        .white, Color(white: 0.62), .black, .red, .orange, .yellow,
        .green, .mint, .cyan, .blue, .purple, .pink,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color)
                    .frame(width: 46, height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.primary.opacity(0.2)))
                TextField("#RRGGBB", text: $hexText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { applyHex() }
            }

            channel("红", rB)
            channel("绿", gB)
            channel("蓝", bB)
            channel("不透明", aB, max: 100, suffix: "%")

            Divider()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(Array(presets.enumerated()), id: \.offset) { _, c in
                    Button { setFull(c) } label: {
                        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(c)
                            .frame(height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.primary.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .onHover { h in if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }
                }
            }
        }
        .padding(14)
        .onAppear { hexText = color.hexString() }
        .onChange(of: color) { _ in hexText = color.hexString() }
    }

    // 0...255 通道
    private var rB: Binding<Double> { Binding(get: { color.rgba().r * 255 }, set: { setComp(r: $0 / 255) }) }
    private var gB: Binding<Double> { Binding(get: { color.rgba().g * 255 }, set: { setComp(g: $0 / 255) }) }
    private var bB: Binding<Double> { Binding(get: { color.rgba().b * 255 }, set: { setComp(b: $0 / 255) }) }
    private var aB: Binding<Double> { Binding(get: { color.rgba().a * 100 }, set: { setComp(a: $0 / 100) }) }

    private func setComp(r: Double? = nil, g: Double? = nil, b: Double? = nil, a: Double? = nil) {
        let c = color.rgba()
        color = Color(.sRGB, red: r ?? c.r, green: g ?? c.g, blue: b ?? c.b, opacity: a ?? c.a)
    }

    private func setFull(_ c: Color) {
        let a = color.rgba().a; let cc = c.rgba()
        color = Color(.sRGB, red: cc.r, green: cc.g, blue: cc.b, opacity: a)
    }

    private func applyHex() {
        var s = hexText.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 6, let v = Int(s, radix: 16) {
            let a = color.rgba().a
            color = Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                          blue: Double(v & 0xFF) / 255, opacity: a)
        } else {
            hexText = color.hexString()   // 非法输入还原
        }
    }

    private func channel(_ label: String, _ binding: Binding<Double>, max: Double = 255, suffix: String = "") -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12)).frame(width: 32, alignment: .leading)
            Slider(value: binding, in: 0...max)
            Text("\(Int(binding.wrappedValue.rounded()))\(suffix)")   // 四舍五入显示，免 57% 显示成 56
                .font(.system(size: 11).monospacedDigit()).foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}
