//
//  SleepTimerPicker.swift
//  BookVault
//
//  Sheet for arming, extending, and cancelling the sleep timer.
//  Mirrors PlaybackSpeedPicker's structure and presentation.
//

import SwiftUI

struct SleepTimerPicker: View {
    let currentState: SleepTimerState
    let hasChapters: Bool
    let lastUsedDuration: TimeInterval
    let currentTime: TimeInterval
    let onSelectDuration: (TimeInterval) -> Void
    /// The chapter boundary is resolved by the caller, which owns the player.
    let onSelectEndOfChapter: () -> Void
    let onCancel: () -> Void
    let onExtend: () -> Void

    /// Drives the countdown readout at the top of the sheet.
    @State private var tick = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isArmed: Bool {
        if case .off = currentState { return false }
        return true
    }

    private var activeMode: SleepTimerMode? {
        switch currentState {
        case .off: nil
        case let .armed(mode, _), let .fading(mode, _): mode
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isArmed {
                    armedHeader
                }

                List {
                    // Turn-off sits above the presets, not below them. Killing a
                    // running timer is the most likely reason to reopen this
                    // sheet, and with the armed header taking the top third,
                    // anything after the preset list falls below the fold.
                    if isArmed {
                        Section {
                            Button(role: .destructive) {
                                onCancel()
                            } label: {
                                Label("Turn Off Sleep Timer", systemImage: "moon.slash")
                            }
                        }
                    }

                    Section {
                        ForEach(SleepTimerManager.presets, id: \.self) { preset in
                            presetRow(preset)
                        }
                    } header: {
                        Text(isArmed ? "Change To" : "Pause After")
                    }

                    Section {
                        endOfChapterRow
                    } footer: {
                        if !hasChapters {
                            Text("This book has no chapter information.")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onReceive(ticker) { tick = $0 }
    }

    // MARK: - Subviews

    private var armedHeader: some View {
        VStack(spacing: 12) {
            Text(
                SleepTimerManager.countdownText(
                    for: currentState,
                    now: tick,
                    currentTime: currentTime
                ) ?? "--:--"
            )
            .font(.system(size: 44, weight: .bold, design: .rounded))
            .monospacedDigit()

            Text("until playback pauses")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                onExtend()
            } label: {
                Label("Add 15 Minutes", systemImage: "plus.circle")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(8)
            }
            .foregroundStyle(.primary)
        }
        .padding(.top, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }

    private func presetRow(_ preset: TimeInterval) -> some View {
        Button {
            onSelectDuration(preset)
        } label: {
            HStack {
                Text(label(for: preset))
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected(preset) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var endOfChapterRow: some View {
        Button {
            onSelectEndOfChapter()
        } label: {
            HStack {
                Label("End of Chapter", systemImage: "book.closed")
                    .foregroundStyle(hasChapters ? .primary : .secondary)
                Spacer()
                if isEndOfChapterActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
        }
        .disabled(!hasChapters)
    }

    private var isEndOfChapterActive: Bool {
        if case .endOfChapter? = activeMode { return true }
        return false
    }

    // MARK: - Helpers

    /// Checked when armed to that duration; otherwise the remembered choice is
    /// shown so the sheet opens with a sensible default highlighted.
    private func isSelected(_ preset: TimeInterval) -> Bool {
        if case let .duration(active)? = activeMode {
            return active == preset
        }
        return !isArmed && preset == lastUsedDuration
    }

    private func label(for preset: TimeInterval) -> String {
        let minutes = Int(preset / 60)
        if minutes >= 60, minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return "\(minutes) minutes"
    }
}

// MARK: - Previews

#Preview("Sleep Timer - Off") {
    SleepTimerPicker(
        currentState: .off,
        hasChapters: true,
        lastUsedDuration: 30 * 60,
        currentTime: 0,
        onSelectDuration: { _ in },
        onSelectEndOfChapter: {},
        onCancel: {},
        onExtend: {}
    )
}

#Preview("Sleep Timer - Armed") {
    SleepTimerPicker(
        currentState: .armed(
            mode: .duration(15 * 60),
            fireDate: Date().addingTimeInterval(12 * 60 + 45)
        ),
        hasChapters: true,
        lastUsedDuration: 15 * 60,
        currentTime: 0,
        onSelectDuration: { _ in },
        onSelectEndOfChapter: {},
        onCancel: {},
        onExtend: {}
    )
}

#Preview("Sleep Timer - No Chapters") {
    SleepTimerPicker(
        currentState: .off,
        hasChapters: false,
        lastUsedDuration: 30 * 60,
        currentTime: 0,
        onSelectDuration: { _ in },
        onSelectEndOfChapter: {},
        onCancel: {},
        onExtend: {}
    )
}
