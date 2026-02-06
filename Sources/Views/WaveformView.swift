import SwiftUI

/// Animated waveform visualization for recording state
/// Inspired by Siri/Raycast voice input animations
struct WaveformView: View {
    let audioLevel: Float  // 0.0 to 1.0
    let isAnimating: Bool

    // Number of bars in the waveform
    private let barCount = 5
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 24
    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 3

    @State private var animationPhases: [Double] = []

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    height: barHeight(for: index),
                    isAnimating: isAnimating,
                    animationDelay: Double(index) * 0.1
                )
                .frame(width: barWidth)
            }
        }
        .frame(height: maxHeight)
        .onAppear {
            animationPhases = (0..<barCount).map { _ in Double.random(in: 0...1) }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard isAnimating else {
            return minHeight
        }

        // Create a natural-looking waveform based on audio level
        // Center bars are taller, edges are shorter
        let centerIndex = Double(barCount - 1) / 2.0
        let distanceFromCenter = abs(Double(index) - centerIndex)
        let centerWeight = 1.0 - (distanceFromCenter / centerIndex) * 0.4

        let normalizedLevel = CGFloat(audioLevel) * centerWeight
        let height = minHeight + (maxHeight - minHeight) * normalizedLevel

        return max(minHeight, min(maxHeight, height))
    }
}

/// Individual animated bar in the waveform
struct WaveformBar: View {
    let height: CGFloat
    let isAnimating: Bool
    let animationDelay: Double

    @State private var currentHeight: CGFloat = 4
    @State private var animationTimer: Timer?

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.white, Color.white.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: currentHeight)
            .animation(.easeInOut(duration: 0.15), value: currentHeight)
            .onChange(of: height) { newHeight in
                currentHeight = newHeight
            }
            .onChange(of: isAnimating) { animating in
                if animating {
                    startIdleAnimation()
                } else {
                    stopIdleAnimation()
                    currentHeight = 4
                }
            }
            .onAppear {
                currentHeight = height
                if isAnimating {
                    startIdleAnimation()
                }
            }
            .onDisappear {
                stopIdleAnimation()
            }
    }

    private func startIdleAnimation() {
        // Add subtle idle animation when audio level is low
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.2 + animationDelay, repeats: true) { _ in
            if height < 8 {
                // Subtle pulse when quiet
                let randomHeight = CGFloat.random(in: 4...8)
                withAnimation(.easeInOut(duration: 0.15)) {
                    currentHeight = randomHeight
                }
            }
        }
    }

    private func stopIdleAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}

/// A more dynamic waveform that shows the actual audio waveform shape
struct LiveWaveformView: View {
    let audioLevel: Float
    let isActive: Bool

    @State private var waveformValues: [CGFloat] = Array(repeating: 0.1, count: 20)
    @State private var timer: Timer?

    private let barWidth: CGFloat = 2
    private let spacing: CGFloat = 2
    private let maxHeight: CGFloat = 32

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<waveformValues.count, id: \.self) { index in
                Rectangle()
                    .fill(barColor(for: index))
                    .frame(width: barWidth, height: waveformValues[index] * maxHeight)
            }
        }
        .frame(height: maxHeight)
        .onAppear {
            startWaveformUpdate()
        }
        .onDisappear {
            stopWaveformUpdate()
        }
        .onChange(of: isActive) { active in
            if active {
                startWaveformUpdate()
            } else {
                stopWaveformUpdate()
                // Fade out
                withAnimation(.easeOut(duration: 0.3)) {
                    waveformValues = Array(repeating: 0.1, count: waveformValues.count)
                }
            }
        }
    }

    private func barColor(for index: Int) -> Color {
        // Gradient effect from center outward
        let center = waveformValues.count / 2
        let distance = abs(index - center)
        let opacity = 1.0 - (Double(distance) / Double(center)) * 0.4
        return Color.white.opacity(opacity)
    }

    private func startWaveformUpdate() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            updateWaveform()
        }
    }

    private func stopWaveformUpdate() {
        timer?.invalidate()
        timer = nil
    }

    private func updateWaveform() {
        guard isActive else { return }

        // Shift values left
        var newValues = Array(waveformValues.dropFirst())

        // Add new value based on audio level with some randomness
        let baseLevel = CGFloat(audioLevel)
        let variation = CGFloat.random(in: -0.1...0.1)
        let newValue = max(0.1, min(1.0, baseLevel + variation))
        newValues.append(newValue)

        withAnimation(.linear(duration: 0.05)) {
            waveformValues = newValues
        }
    }
}

// MARK: - Preview

struct WaveformView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            // Simple waveform
            VStack {
                Text("Simple Waveform").font(.caption)
                WaveformView(audioLevel: 0.5, isAnimating: true)
            }

            // Live waveform
            VStack {
                Text("Live Waveform").font(.caption)
                LiveWaveformView(audioLevel: 0.6, isActive: true)
            }
        }
        .padding(40)
        .background(Color.black.opacity(0.9))
        .preferredColorScheme(.dark)
    }
}
