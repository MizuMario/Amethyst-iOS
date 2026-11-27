import SwiftUI
import UIKit

@available(iOS 17.0, *)
struct LauncherWorkspace: View {
    @ObservedObject var profiles: ProfileBrowserState
    let settings: (String) -> UIViewController
    let jitStatus: () -> Bool
    let accountImage: () -> UIImage?
    let downloadSnapshot: () -> [String: Any]
    let prepareDirectory: (String) -> String?
    let blockTexture: (String, String) -> UIImage?
    let blockTextures: (String) -> [String]
    let saveJava: (String, [String: String]) -> Bool
    let action: (String, String) -> Void
    private enum LauncherTab {
        case instances, downloads, settings

        var title: LocalizedStringKey {
            switch self {
            case .instances: "インスタンス"
            case .downloads: "ダウンロード"
            case .settings: "設定"
            }
        }

        var icon: String {
            switch self {
            case .instances: "square.grid.2x2"
            case .downloads: "arrow.down.to.line"
            case .settings: "gearshape"
            }
        }
    }

    @State private var tab: LauncherTab = .instances
    @State private var showCreate = false
    @State private var headImage: UIImage?
    @State private var download = LauncherDownloadState()
    @State private var search = ""
    @State private var jitReady = false
    @State private var iconOverrides: [String: String] = [:]
    @State private var instancePath: [ProfileSelection] = []
    @State private var pendingCommand: (String, String)?

    private var filteredRows: [[String: String]] {
        profiles.snapshot.rows.filter {
            search.isEmpty || [$0["name"], $0["version"]].compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        tabs
        .onChange(of: profiles.snapshot.rows.compactMap { $0["id"] }) { _, keys in
            if instancePath.contains(where: { !keys.contains($0.id) }) {
                instancePath.removeAll()
            }
        }
        .task {
            while !Task.isCancelled {
                jitReady = jitStatus()
                let image = accountImage()
                if headImage !== image { headImage = image }
                let snapshot = LauncherDownloadState(downloadSnapshot())
                if snapshot != download { download = snapshot }
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { break }
            }
        }
        .sheet(isPresented: $showCreate, onDismiss: dispatchCommand) {
            LauncherCreateSheet { command in
                pendingCommand = (command, "")
                showCreate = false
            }
        }

    }

    @ViewBuilder private var tabs: some View {
        if #available(iOS 26.0, *) {
            TabView(selection: $tab) {
                Tab(LauncherTab.instances.title, systemImage: LauncherTab.instances.icon, value: LauncherTab.instances) {
                    instanceNavigation
                }
                Tab(LauncherTab.downloads.title, systemImage: LauncherTab.downloads.icon, value: LauncherTab.downloads) {
                    LauncherDownloadsView(download: download)
                }
                Tab(LauncherTab.settings.title, systemImage: LauncherTab.settings.icon, value: LauncherTab.settings) {
                    LauncherSettingsIndex(makeController: settings)
                }
            }
            .tabViewStyle(.tabBarOnly)
            .tabBarMinimizeBehavior(.never)
        } else {
            TabView(selection: $tab) {
                instanceNavigation
                    .tabItem { Label(LauncherTab.instances.title, systemImage: LauncherTab.instances.icon) }
                    .tag(LauncherTab.instances)
                LauncherDownloadsView(download: download)
                    .tabItem { Label(LauncherTab.downloads.title, systemImage: LauncherTab.downloads.icon) }
                    .tag(LauncherTab.downloads)
                LauncherSettingsIndex(makeController: settings)
                    .tabItem { Label(LauncherTab.settings.title, systemImage: LauncherTab.settings.icon) }
                    .tag(LauncherTab.settings)
            }
        }
    }

    private func dispatchCommand() {
        guard let (command, key) = pendingCommand else { return }
        pendingCommand = nil
        if command == "play" { tab = .downloads }
        action(command, key)
    }

    private var instanceNavigation: some View {
        NavigationStack(path: $instancePath) {
            library
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: ProfileSelection.self) { selection in
                    let row = profiles.snapshot.rows.first { $0["id"] == selection.id } ?? selection.row
                    ProfileActions(row: row, initialPage: selection.page,
                                   prepareDirectory: prepareDirectory,
                                   iconPicker: {
                                       let version = row["version"] ?? ""
                                       let selected = iconOverrides[selection.id] ?? row["iconTexture"] ?? ""
                                       return AnyView(BlockIconPicker(version: version, selected: selected,
                                           textures: blockTextures, load: blockTexture) { texture in
                                               guard saveJava(selection.id, ["iconTexture": texture]) else { return false }
                                               iconOverrides[selection.id] = texture
                                               return true
                                           })
                                   },
                                   saveJava: { saveJava(selection.id, $0) }) { command in
                        if command == "play" {
                            instancePath.removeAll()
                            tab = .downloads
                        }
                        action(command, selection.id)
                    }
                    .toolbar(.visible, for: .navigationBar)
                }
        }
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 18) {
                    Text("インスタンス").font(.title2.bold())
                    Spacer()
                    Button {
                        action("jit", "")
                    } label: {
                        Image(systemName: jitReady ? "bolt.circle.fill" : "bolt.slash.circle")
                            .foregroundStyle(jitReady ? Color.green : Color.secondary)
                    }
                    .accessibilityLabel(jitReady ? "JITは有効" : "JITを有効にする")
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel("インスタンスを追加")
                    Button {
                        action("account", "")
                    } label: {
                        if let image = headImage ?? UIImage(named: "DefaultAccount") {
                            Image(uiImage: image)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                        } else {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                    .accessibilityLabel("アカウント")
                }
                .font(.title2)
                searchBar
                if filteredRows.isEmpty {
                    ContentUnavailableView("インスタンスがありません", systemImage: "cube")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], spacing: 8) {
                    ForEach(filteredRows, id: \.self) { row in
                        NavigationLink(value: ProfileSelection(row: row, page: .launch)) {
                            let instance = profileInstance(row)
                            VStack(spacing: 4) {
                                MinecraftBlockIcon(version: row["version"] ?? instance.version,
                                                   texture: iconName(for: row, loader: instance.loader),
                                                   load: blockTexture)
                                    .frame(width: 58, height: 58)
                                Text(instance.name).font(.subheadline.weight(.medium)).lineLimit(2)
                                Text(row["version"] ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 105)
                            .padding(8)
                            .background(profiles.snapshot.selected == row["id"] ? Color.accentColor.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("その他", systemImage: "ellipsis.circle") {
                                instancePath.append(.init(row: row, page: .other))
                            }
                            if row["canDelete"] == "1" {
                                Button("削除", systemImage: "trash", role: .destructive) {
                                    action("delete", row["id"] ?? "")
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func iconName(for row: [String: String], loader: InstanceLoader) -> String {
        let chosen = iconOverrides[row["id"] ?? ""] ?? row["iconTexture"] ?? ""
        return chosen.isEmpty ? (loader == .vanilla ? "grass_block_side" : "amethyst_block") : chosen
    }

    private var searchBar: some View {
        let field = HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("名前・バージョンで検索", text: $search)
                .textFieldStyle(.plain)
            if !search.isEmpty {
                Button("検索語を消去", systemImage: "xmark.circle.fill") { search = "" }
                    .labelStyle(.iconOnly)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        return Group {
            if #available(iOS 26.0, *) {
                field.glassEffect(.regular, in: Capsule())
            } else {
                field.background(.regularMaterial, in: Capsule())
            }
        }
    }
}

@available(iOS 17.0, *)
private struct LauncherSettingsIndex: View {
    let makeController: (String) -> UIViewController
    private let sections = [
        ("general", "gearshape"), ("video", "display"), ("control", "gamecontroller"),
        ("java", "cup.and.saucer"), ("debug", "ladybug")
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.0) { key, icon in
                    let localizationKey = "preference.section." + key
                    let fallback = Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
                    let title = Bundle.main.localizedString(forKey: localizationKey,
                        value: fallback?.localizedString(forKey: localizationKey, value: nil, table: nil), table: nil)
                    NavigationLink {
                        LegacySettings(makeController: { makeController(key) })
                            .navigationTitle(title)
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label(title, systemImage: icon)
                    }
                }
            }
            .navigationTitle("設定")
        }
    }
}

private struct LegacySettings: UIViewControllerRepresentable {
    let makeController: () -> UIViewController
    func makeUIViewController(context: Context) -> UIViewController { makeController() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

private enum ProfilePage: String, CaseIterable {
    case launch = "起動", mods = "Mod一覧", logs = "ログ", java = "Java", other = "その他"
}

private struct ProfileSelection: Identifiable, Hashable {
    let row: [String: String]
    let page: ProfilePage
    var id: String { row["id"] ?? "" }
}

private func profileInstance(_ row: [String: String]) -> LauncherInstance {
    let id = row["version"] ?? ""
    let patterns: [(InstanceLoader, String)] = [
        (.fabric, #"^fabric-loader-[^-]+-(.+)$"#), (.quilt, #"^quilt-loader-[^-]+-(.+)$"#),
        (.neoForge, #"^(.+)-neoforge-.+$"#), (.forge, #"^(.+)-forge-.+$"#)
    ]
    for (loader, pattern) in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)),
           let range = Range(match.range(at: 1), in: id) {
            return .init(name: row["name"] ?? id, version: String(id[range]), loader: loader, group: "")
        }
    }
    return .init(name: row["name"] ?? id, version: id, loader: .vanilla, group: "")
}

@available(iOS 17.0, *)
private struct ProfileActions: View {
    let row: [String: String]
    let initialPage: ProfilePage
    let prepareDirectory: (String) -> String?
    let iconPicker: () -> AnyView
    let saveJava: ([String: String]) -> Bool
    let action: (String) -> Void
    @State private var selectedPage: ProfilePage?
    @State private var curseForgeKey = ""
    @State private var busy = false
    @State private var log = ""
    @State private var savedJava: [String: String]?
    @State private var modDirectory: URL?
    @State private var directoryFailed = false

    var body: some View {
        let instance = profileInstance(row)
        let tab = selectedPage ?? initialPage
        VStack(spacing: 0) {
            Picker("表示", selection: Binding(get: { tab }, set: { selectedPage = $0 })) {
                ForEach(ProfilePage.allCases.filter { $0 != .mods || instance.loader != .vanilla }, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)
            .disabled(busy)
            switch tab {
            case .launch:
                Form {
                    LabeledContent("Minecraft", value: row["version"] ?? "")
                    Button("起動", systemImage: "play.fill") { action("play") }
                }
            case .mods:
                Group {
                    if let modDirectory {
                        InstanceModsView(instance: instance, gameDirectory: modDirectory,
                                         curseForgeKey: $curseForgeKey, busy: $busy)
                    } else if directoryFailed {
                        ContentUnavailableView("Modフォルダを準備できませんでした", systemImage: "folder.badge.questionmark")
                    } else {
                        ProgressView("Modフォルダを準備中…")
                    }
                }
                .task {
                    guard modDirectory == nil, !directoryFailed else { return }
                    if let id = row["id"], let path = prepareDirectory(id) {
                        modDirectory = URL(fileURLWithPath: path)
                    } else {
                        directoryFailed = true
                    }
                }
            case .logs:
                ScrollView {
                    Text(log.isEmpty ? "ログはありません" : log)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .task {
                    guard let path = row["log"], let handle = FileHandle(forReadingAtPath: path) else { return }
                    defer { try? handle.close() }
                    if let size = try? handle.seekToEnd() {
                        try? handle.seek(toOffset: size > 65536 ? size - 65536 : 0)
                        if let data = try? handle.read(upToCount: 65536) {
                            log = String(decoding: data, as: UTF8.self)
                        }
                    }
                }
            case .java:
                InstanceJavaSettings(row: row.merging(savedJava ?? [:]) { _, saved in saved }) { values in
                    guard saveJava(values) else { return false }
                    savedJava = values
                    return true
                }
            case .other:
                Form {
                    NavigationLink {
                        iconPicker()
                    } label: {
                        Label("アイコンを変更", systemImage: "cube")
                    }
                    Button("インスタンス設定", systemImage: "gearshape") { action("edit") }
                    Button("複製", systemImage: "plus.square.on.square") { action("duplicate") }
                    if row["canDelete"] == "1" {
                        Button("削除", systemImage: "trash", role: .destructive) { action("delete") }
                    }
                }
            }
        }
        .navigationTitle(instance.name)
        .toolbar {
            if tab == .logs, let path = row["log"], FileManager.default.isReadableFile(atPath: path) {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: URL(fileURLWithPath: path)) {
                        Label("ログを共有", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(busy)
    }
}
@available(iOS 17.0, *)
struct MinecraftBlockIcon: View {
    let version: String
    let texture: String
    let load: (String, String) -> UIImage?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
            } else {
                Image(systemName: "cube.fill").font(.system(size: 38)).foregroundStyle(.secondary)
            }
        }
        .task(id: version + "/" + texture) { image = load(version, texture) }
        .accessibilityHidden(true)
    }
}
