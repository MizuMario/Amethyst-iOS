import SwiftUI
import UIKit

@available(iOS 17.0, *)
struct BlockIconPicker: View {
    let version: String
    let selected: String
    let textures: (String) -> [String]
    let load: (String, String) -> UIImage?
    let save: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var names: [String] = []
    @State private var search = ""
    @State private var loaded = false
    @State private var saveFailed = false

    var body: some View {
        ScrollView {
            if loaded && names.isEmpty {
                ContentUnavailableView("テクスチャが見つかりません",
                    systemImage: "cube", description: Text("Minecraftをインストールすると選択できます。"))
            }
            Button("既定のアイコンを使う") { select("") }.padding()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 12)], spacing: 12) {
                ForEach(names.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search.replacingOccurrences(of: " ", with: "_")) }, id: \.self) { name in
                    Button {
                        select(name)
                    } label: {
                        VStack(spacing: 6) {
                            MinecraftBlockIcon(version: version, texture: name, load: load)
                                .frame(width: 46, height: 46)
                            Text(name.replacingOccurrences(of: "_", with: " "))
                                .font(.caption).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 86)
                        .background(selected == name ? Color.accentColor.opacity(0.13) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected == name ? .isSelected : [])
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("ブロックアイコン")
        .searchable(text: $search, prompt: "テクスチャ名で検索")
        .task {
            names = textures(version)
            loaded = true
        }
        .alert("アイコンを保存できませんでした", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func select(_ name: String) {
        if save(name) { dismiss() }
        else { saveFailed = true }
    }
}
