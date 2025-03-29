//
//  BarWaveformView.swift
//  YapNotes
//
//  Created by William Lu on 3/27/25.
//
import SwiftUI


struct BarWaveformView: View {
    let barAmplitudes: [CGFloat]
    let maxBarHeight: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let barCount = barAmplitudes.count
            let spacing: CGFloat = 2
            let totalSpacing = CGFloat(barCount - 1) * spacing
            let availableWidth = geometry.size.width - totalSpacing
            let barWidth = availableWidth / CGFloat(barCount)

            VStack(spacing: 0) {
                Spacer()
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { i in
                        let amplitude = barAmplitudes[i]
                        let scaledHeight = min(sqrt(amplitude) * maxBarHeight, maxBarHeight)
                        RoundedCorners(radius: 3, corners: [.topLeft, .topRight])
                            .fill(Color.white)
                            .frame(width: barWidth, height: scaledHeight)
                    }
                }
            }
        }
    }
}

struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
