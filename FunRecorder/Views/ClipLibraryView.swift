import SwiftUI
import SwiftData

struct ClipLibraryView: View {
    @Query(sort: \Clip.createdAt, order: .reverse) private var clips: [Clip]
    @Environment(\.modelContext) private var context
    let viewModel: RecorderViewModel

    @State private var clipToDelete: Clip? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Saved Clips")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)

            if clips.isEmpty {
                Text("No saved clips")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                List {
                    ForEach(clips) { clip in
                        ClipRowView(clip: clip)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                try? viewModel.load(clip: clip)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    clipToDelete = clip
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: 260)
            }
        }
        .confirmationDialog(
            "Delete \"\(clipToDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { clipToDelete != nil },
                set: { if !$0 { clipToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let clip = clipToDelete {
                    try? viewModel.delete(clip: clip, context: context)
                }
                clipToDelete = nil
            }
            Button("Cancel", role: .cancel) { clipToDelete = nil }
        }
    }
}

// MARK: - ClipRowView

private struct ClipRowView: View {
    let clip: Clip

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.name).font(.body)
                if let bpm = clip.detectedTempoBPM {
                    Text(String(format: "%.0f BPM", bpm))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(durationString(clip.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(dateString(clip.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func durationString(_ d: TimeInterval) -> String {
        let total = Int(d)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f.string(from: date)
    }
}
