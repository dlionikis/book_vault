//
//  PlaybackSpeedPicker.swift
//  BookVault
//
//  Extracted from NowPlayingView.swift for reuse across Settings and Player
//

import SwiftUI

/// A picker for selecting playback speed with fine-grained control
/// Supports 0.5x to 3.0x in 0.05 increments with quick presets
struct PlaybackSpeedPicker: View {
    let currentRate: Float
    let onSelect: (Float) -> Void

    // Speed range: 0.5x to 3.0x in 0.05 increments
    private let minSpeed: Float = 0.5
    private let maxSpeed: Float = 3.0
    private let increment: Float = 0.05

    // Quick presets for common speeds
    private let presets: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    @State private var selectedRate: Float

    init(currentRate: Float, onSelect: @escaping (Float) -> Void) {
        self.currentRate = currentRate
        self.onSelect = onSelect
        self._selectedRate = State(initialValue: currentRate)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Current speed display
                VStack(spacing: 4) {
                    Text(String(format: "%.2fx", selectedRate))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Playback Speed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                // Fine-grained stepper controls
                HStack(spacing: 16) {
                    // Decrease by 0.05
                    Button {
                        adjustSpeed(by: -increment)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(selectedRate > minSpeed ? .blue : .gray.opacity(0.3))
                    }
                    .disabled(selectedRate <= minSpeed)

                    // Slider for continuous adjustment
                    Slider(
                        value: Binding(
                            get: { selectedRate },
                            set: { newValue in
                                // Round to nearest 0.05
                                selectedRate = roundToIncrement(newValue)
                            }
                        ),
                        in: minSpeed ... maxSpeed,
                        step: increment
                    )
                    .tint(.blue)

                    // Increase by 0.05
                    Button {
                        adjustSpeed(by: increment)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(selectedRate < maxSpeed ? .blue : .gray.opacity(0.3))
                    }
                    .disabled(selectedRate >= maxSpeed)
                }
                .padding(.horizontal, 20)

                // Quick preset buttons
                VStack(spacing: 12) {
                    Text("Quick Presets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    HStack(spacing: 12) {
                        ForEach(presets, id: \.self) { speed in
                            Button {
                                selectedRate = speed
                            } label: {
                                Text(String(format: "%.2gx", speed))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(abs(selectedRate - speed) < 0.01 ? Color.blue : Color.gray.opacity(0.15))
                                    )
                                    .foregroundStyle(abs(selectedRate - speed) < 0.01 ? .white : .primary)
                            }
                        }
                    }
                }

                Spacer()

                // Apply button
                Button {
                    onSelect(selectedRate)
                } label: {
                    Text("Apply")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Playback Speed")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func adjustSpeed(by amount: Float) {
        let newSpeed = selectedRate + amount
        selectedRate = max(minSpeed, min(maxSpeed, roundToIncrement(newSpeed)))
    }

    private func roundToIncrement(_ value: Float) -> Float {
        (value / increment).rounded() * increment
    }
}

// MARK: - Previews

#Preview("Speed Picker - 1x") {
    PlaybackSpeedPicker(currentRate: 1.0) { rate in
        print("Selected rate: \(rate)")
    }
}

#Preview("Speed Picker - 1.4x") {
    PlaybackSpeedPicker(currentRate: 1.4) { rate in
        print("Selected rate: \(rate)")
    }
}
