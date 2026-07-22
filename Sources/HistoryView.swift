import SwiftUI

/// Every song Resonance has recognized, newest first — the answer to "what
/// was that song at the café" after the moment has passed.
struct HistoryView: View {
    let history: MatchHistoryStore

    var body: some View {
        VStack(spacing: 0) {
            if history.entries.isEmpty {
                emptyState
            } else {
                List(history.entries) { entry in
                    HistoryRow(entry: entry) {
                        history.remove(entry)
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            footer
        }
        .frame(width: 380, height: 460)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No songs recognized yet")
                .foregroundStyle(.secondary)
            Text("Songs Resonance recognizes appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("\(history.entries.count) songs")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear History") {
                history.clear()
            }
            .controlSize(.small)
            .disabled(history.entries.isEmpty)
        }
        .padding(10)
    }
}

private struct HistoryRow: View {
    let entry: MatchHistoryEntry
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(url: entry.artworkURL, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(.body).lineLimit(1)
                HStack(spacing: 4) {
                    if let artist = entry.artist {
                        Text(artist).lineLimit(1)
                        Text(verbatim: "·")
                    }
                    Text(entry.recognizedAt, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let url = entry.appleMusicURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.forward.app")
                        .accessibilityLabel("Open in Apple Music")
                }
                .foregroundStyle(.secondary)
                .help("Open in Apple Music")
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Remove from History", role: .destructive) {
                onRemove()
            }
        }
    }
}
