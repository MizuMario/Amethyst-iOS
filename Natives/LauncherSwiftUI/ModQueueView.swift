import SwiftUI

@available(iOS 17.0, *)
struct ModQueueView: View {
    let items: [QueuedMod]
    let requestedIDs: Set<String>
    let busy: Bool
    let notice: String?
    let download: () -> Void
    let clear: () -> Void

    var body: some View {
        List {
            if busy { ProgressView("処理中…") }
            if let notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            if items.isEmpty {
                ContentUnavailableView(
                    "キューは空です", systemImage: "tray",
                    description: Text("検索結果を左へスワイプしてModを追加できます。")
                )
            } else {
                Section("取得予定") {
                    ForEach(items) { item in
                        HStack {
                            ModArtworkView(mod: item.project)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.project.name)
                                Text(requestedIDs.contains(item.id) ? item.release.name : item.release.name + " · 必須依存")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Button("まとめてダウンロード", systemImage: "arrow.down.circle", action: download)
                    Button("キューを空にする", action: clear)
                }
                .disabled(busy)
            }
        }
        .navigationTitle("ダウンロードキュー")
        .navigationBarBackButtonHidden(busy)
    }
}

@available(iOS 17.0, *)
struct ModArtworkView: View {
    let mod: CatalogMod
    var size: CGFloat = 40

    var body: some View {
        let url = mod.iconURL.flatMap { $0.scheme == "https" ? $0 : nil }
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}
