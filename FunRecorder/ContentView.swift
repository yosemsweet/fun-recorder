import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var viewModel = RecorderViewModel()
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(spacing: 0) {
            waveformArea
                .frame(height: 160)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12)
                .padding(.top, 12)

            controlsArea
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

            Divider()

            ClipLibraryView(viewModel: viewModel)
        }
    }

    // MARK: - Waveform area (state-dependent)

    @ViewBuilder
    private var waveformArea: some View {
        switch viewModel.appState {
        case .empty:
            VStack(spacing: 8) {
                Image(systemName: "mic.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Tap Record to capture an idea")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .recording:
            VStack(spacing: 4) {
                LiveWaveformView(levels: viewModel.levels)
                    .padding(.horizontal, 8)
                Text(String(format: "%.1fs / 30s", viewModel.recorder.recordedDuration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .editing:
            VStack(spacing: 4) {
                if let url = viewModel.currentURL {
                    WaveformRegionView(
                        audioURL: url,
                        duration: viewModel.currentDuration,
                        totalSamples: Int(viewModel.currentDuration * AudioRecorder.sampleRate),
                        beatGrid: viewModel.beatGrid,
                        regionStartSamples: viewModel.regionStartSamples,
                        regionEndSamples: viewModel.regionEndSamples,
                        onRegionChanged: { start, end in
                            viewModel.updateRegion(startSamples: start, endSamples: end)
                        },
                        beatLabel: { time in viewModel.beatLabel(for: time) }
                    )
                }
                if viewModel.beatGrid == nil && viewModel.currentDuration > 0 {
                    Text("No tempo detected — freeform selection")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controlsArea: some View {
        VStack(spacing: 10) {
            // Save rename field (visible while pendingSaveName is set)
            if let _ = viewModel.pendingSaveName {
                HStack {
                    TextField(
                        "Clip name",
                        text: Binding(
                            get: { viewModel.pendingSaveName ?? "" },
                            set: { viewModel.pendingSaveName = $0.isEmpty ? nil : $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit {
                        try? viewModel.confirmSave(name: viewModel.pendingSaveName ?? "", context: context)
                    }

                    Button("Save") {
                        try? viewModel.confirmSave(name: viewModel.pendingSaveName ?? "", context: context)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Cancel") { viewModel.cancelSave() }
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Main control row
            HStack(spacing: 32) {
                // Record / Stop
                Button {
                    Task {
                        if viewModel.appState == .recording {
                            await viewModel.stopRecording()
                        } else {
                            try? await viewModel.startRecording()
                        }
                    }
                } label: {
                    Image(systemName: viewModel.appState == .recording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(viewModel.appState == .recording ? .red : .accentColor)
                        .symbolEffect(.pulse, isActive: viewModel.appState == .recording)
                }

                if viewModel.appState == .editing {
                    // Play / Pause
                    Button { viewModel.togglePlayback() } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                    }

                    // Loop toggle
                    Button { viewModel.isLooping.toggle() } label: {
                        Image(systemName: "repeat")
                            .font(.title2)
                            .foregroundStyle(viewModel.isLooping ? .accentColor : .secondary)
                    }

                    // Save
                    Button { viewModel.beginSave() } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title2)
                    }

                    // New recording
                    Button { viewModel.newRecording() } label: {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.appState)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Clip.self, inMemory: true)
}
