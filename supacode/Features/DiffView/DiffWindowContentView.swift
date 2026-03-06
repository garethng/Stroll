import SwiftUI
import YiTong

struct DiffWindowContentView: View {
  var state: DiffWindowState

  private var selectedFileID: Binding<String?> {
    Binding(
      get: { state.selectedFile?.id },
      set: { id in
        if let id, let file = state.changedFiles.first(where: { $0.id == id }) {
          state.selectFile(file)
        }
      },
    )
  }

  var body: some View {
    NavigationSplitView {
      fileListSidebar
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)
    } detail: {
      diffDetail
    }
  }

  // MARK: - File List

  private var fileListSidebar: some View {
    List(selection: selectedFileID) {
      ForEach(state.changedFiles) { file in
        FileRowView(file: file)
          .tag(file.id)
      }
    }
    .listStyle(.sidebar)
    .overlay {
      if state.isLoadingFiles && state.changedFiles.isEmpty {
        ProgressView()
      } else if !state.isLoadingFiles && state.changedFiles.isEmpty {
        ContentUnavailableView(
          "No Changes",
          systemImage: "checkmark.circle",
          description: Text("Working directory is clean"),
        )
      }
    }
  }

  // MARK: - Diff Detail

  private var diffDetail: some View {
    Group {
      if let document = state.diffDocument {
        DiffView(
          document: document,
          configuration: DiffConfiguration(
            style: .split,
            showsFileHeaders: false,
          ),
        )
      } else if state.isLoadingFiles {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView(
          "Select a File",
          systemImage: "doc.text",
          description: Text("Choose a file from the sidebar to view changes"),
        )
      }
    }
  }
}

// MARK: - Status Color

extension DiffFileStatus {
  var color: Color {
    switch self {
    case .modified: .orange
    case .added: .green
    case .deleted: .red
    case .renamed: .blue
    case .copied: .blue
    case .unknown: .secondary
    }
  }
}

// MARK: - File Row

private struct FileRowView: View {
  let file: DiffChangedFile

  var body: some View {
    HStack(spacing: 6) {
      Text(file.statusSymbol)
        .font(.caption)
        .monospaced()
        .foregroundStyle(file.status.color)
        .frame(width: 14, alignment: .center)
      VStack(alignment: .leading, spacing: 1) {
        Text(file.displayName)
          .font(.body)
          .lineLimit(1)
        if !file.directoryPath.isEmpty {
          Text(file.directoryPath)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.head)
        }
      }
    }
  }
}
