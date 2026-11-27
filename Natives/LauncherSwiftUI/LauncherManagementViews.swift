import SwiftUI

@available(iOS 17.0, *)
struct LauncherCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let select: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("作成方法") {
                    Button("Vanilla", systemImage: "cube") { select("createVanilla") }
                    Button("Fabric / Quilt", systemImage: "shippingbox") { select("createFabric") }
                    Button("Forge / NeoForge", systemImage: "hammer") { select("createForge") }
                    Button("Modpack", systemImage: "square.stack.3d.up") { select("createModpack") }
                    Button("ファイルから読み込む", systemImage: "folder.badge.plus") { select("importInstance") }
                }
            }
            .navigationTitle("インスタンスを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct LauncherDownloadState: Equatable {
    var name = ""
    var status = "idle"
    var fraction = 0.0
    var detail = ""

    init(_ snapshot: [String: Any] = [:]) {
        name = snapshot["name"] as? String ?? ""
        status = snapshot["status"] as? String ?? "idle"
        fraction = snapshot["fraction"] as? Double ?? 0
        detail = snapshot["detail"] as? String ?? ""
    }
}

@available(iOS 17.0, *)
struct LauncherDownloadsView: View {
    let download: LauncherDownloadState

    var body: some View {
        List {
            if download.status == "idle" {
                ContentUnavailableView("ダウンロードはありません", systemImage: "arrow.down.circle")
            } else {
                Section("インスタンス") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(download.name).font(.headline)
                        ProgressView(value: download.fraction) {
                            Text(statusText)
                        } currentValueLabel: {
                            Text(download.fraction.formatted(.percent.precision(.fractionLength(0))))
                                .monospacedDigit()
                        }
                        if !download.detail.isEmpty {
                            Text(download.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Text("ダウンロード")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.bar)
        }
    }

    private var statusText: String {
        switch download.status {
        case "complete": "ダウンロード完了"
        case "failed": "ダウンロード失敗"
        default: "ダウンロード中"
        }
    }
}
