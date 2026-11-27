import SwiftUI

@available(iOS 17.0, *)
struct InstanceModsView: View {
    let instance: LauncherInstance
    let gameDirectory: URL
    @Binding var curseForgeKey: String
    @State private var provider: ModProvider = .modrinth
    @State private var query = ""
    @State private var results: [CatalogMod] = []
    @State private var searchNotice: String?
    @State private var searching = false
    @State private var nextOffset: Int?
    @State private var failedOffset: Int?
    @State private var activeSearchID = UUID()
    @State private var queueRoots: [QueuedMod] = []
    @State private var queue: [QueuedMod] = []
    @State private var unmanaged: [String] = []
    @State private var installed: [InstalledMod] = []
    @Binding var busy: Bool
    @State private var notice: String?
    @State private var selectedMod: CatalogMod?
    @State private var releases: [ModRelease] = []
    @State private var selectedRelease: String?
    @State private var showFilters = false

    private var catalog: ModCatalog { ModCatalog(instance: instance, curseForgeKey: curseForgeKey) }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    searchScreen
                } label: {
                    Label("Modをダウンロード", systemImage: "arrow.down.circle")
                }
                .disabled(busy)
                feedback
            }
            Section("導入済みMod") {
                if installed.isEmpty && unmanaged.isEmpty {
                    Text("導入済みのModはありません。").foregroundStyle(.secondary)
                }
                ForEach(installed) { item in
                    HStack(spacing: 12) {
                        ModArtworkView(mod: item.project)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text(item.project.name)
                                if item.isDisabled {
                                    Label("無効", systemImage: "pause.circle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(item.version + " · " + item.project.provider.rawValue)
                                .font(.caption).foregroundStyle(.secondary)
                            Button("更新を確認") { download(item.project) }
                                .buttonStyle(.borderless)
                                .disabled(busy)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        // The first action runs when the user swipes all the way.
                        Button(role: .destructive) { deleteInstalled(item) } label: {
                            Label("削除", systemImage: "trash")
                        }
                        .disabled(busy)
                        Button { toggleInstalled(item) } label: {
                            Label(item.isDisabled ? "有効化" : "無効化",
                                  systemImage: item.isDisabled ? "play.circle" : "pause.circle")
                        }
                        .tint(.orange)
                        .disabled(busy)
                    }
                }
                ForEach(unmanaged, id: \.self) { filename in
                    Label(filename, systemImage: "shippingbox")
                }
            }
        }
        .onAppear {
            do {
                let root = try directory()
                let manifest = root.appending(path: ".amethyst-mods.json")
                if FileManager.default.fileExists(atPath: manifest.path) {
                    installed = try JSONDecoder().decode([InstalledMod].self, from: Data(contentsOf: manifest))
                }
                let managed = Set(installed.map(\.file))
                unmanaged = try FileManager.default.contentsOfDirectory(atPath: root.path)
                    .filter { ($0.hasSuffix(".jar") || $0.hasSuffix(".jar.disabled")) && !managed.contains($0) }
                    .sorted()
            } catch { notice = error.localizedDescription }
        }
    }

    private struct SearchInput: Equatable {
        let provider: ModProvider
        let query: String
        let key: String
    }

    private var searchInput: SearchInput {
        SearchInput(
            provider: provider,
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            key: provider == .curseForge ? curseForgeKey.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        )
    }

    private var searchScreen: some View {
        let input = searchInput
        let installedIDs = Set(installed.map(\.id))
        let queuedIDs = Set(queue.map(\.id))
        return List {
            Section {
                Picker("配布元", selection: $provider) {
                    ForEach(ModProvider.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if provider == .curseForge {
                    SecureField("CurseForge APIキー", text: $curseForgeKey)
                }
                TextField("Modを検索…", text: $query)
                Button {
                    showFilters.toggle()
                } label: {
                    HStack {
                        Label("絞り込み条件", systemImage: "line.3.horizontal.decrease")
                        Spacer()
                        Image(systemName: showFilters ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityValue(showFilters ? "展開中" : "折りたたみ中")
                if showFilters {
                    LabeledContent("Minecraft", value: instance.version)
                    LabeledContent("Modローダー", value: instance.loader.rawValue)
                }
            }
            .disabled(busy)

            Section {
                NavigationLink {
                    ModQueueView(
                        items: queue, requestedIDs: Set(queueRoots.map(\.id)),
                        busy: busy, notice: notice,
                        download: downloadQueue, clear: clearQueue
                    )
                } label: {
                    Label("ダウンロードキュー（\(queue.count)）", systemImage: "tray.and.arrow.down")
                }
                .disabled(busy)
            } footer: {
                HStack(spacing: 6) {
                    if busy { ProgressView().controlSize(.small) }
                    Text(notice ?? " ").lineLimit(1)
                        .accessibilityHidden(notice == nil)
                }
                .frame(height: 22, alignment: .leading)
            }

            Section("検索結果") {
                if searching { ProgressView("Modを取得中…") }
                if let searchNotice {
                    Text(searchNotice).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(results) { mod in
                    NavigationLink {
                        modDetails(mod)
                    } label: {
                        HStack(spacing: 12) {
                            ModArtworkView(mod: mod)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    ModStatusIcons(
                                        installed: installedIDs.contains(mod.id),
                                        queued: queuedIDs.contains(mod.id)
                                    )
                                    Text(mod.name).font(.headline).lineLimit(1)
                                }
                                Text(mod.summary).font(.caption).lineLimit(2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(busy)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button { enqueue(mod) } label: {
                            Label("キューに追加", systemImage: "tray.and.arrow.down")
                        }
                        .tint(.accentColor)
                        .disabled(busy)
                    }
                    .contextMenu {
                        Button("キューに追加", systemImage: "tray.and.arrow.down") { enqueue(mod) }
                            .disabled(busy)
                    }
                }
                if let offset = nextOffset, !searching {
                    ProgressView("追加のModを取得中…")
                        .task(id: offset) { await loadNextPage(input, offset: offset) }
                } else if let offset = failedOffset {
                    Button("次の結果を再取得") { failedOffset = nil; nextOffset = offset }
                }
            }
        }
        .navigationTitle("Modをダウンロード")
        .navigationBarBackButtonHidden(busy)
        .task(id: input) { await search(input) }
    }

    private func modDetails(_ mod: CatalogMod) -> some View {
        Form {
            Section {
                HStack {
                    ModArtworkView(mod: mod, size: 56)
                    LabeledContent("配布元", value: mod.provider.rawValue)
                }
                Text(mod.summary)
            }
            Section("バージョンの選択") {
                feedback
                if !releases.isEmpty {
                    Picker("配布ファイル", selection: $selectedRelease) {
                        ForEach(releases, id: \.id) { release in
                            Text(release.name).tag(Optional(release.id))
                        }
                    }
                    .disabled(busy)
                    Button("キューに追加", systemImage: "tray.and.arrow.down") {
                        guard let release = releases.first(where: { $0.id == selectedRelease }) else { return }
                        enqueue(mod, selected: release)
                    }
                    .disabled(busy || selectedRelease == nil)
                }
            }
        }
        .navigationTitle(mod.name)
        .navigationBarBackButtonHidden(busy)
        .onAppear {
            guard selectedMod?.id != mod.id || releases.isEmpty else { return }
            selectedMod = mod
            releases = []
            selectedRelease = nil
            perform {
                releases = try await catalog.releases(mod)
                selectedRelease = releases.first?.id
            }
        }
    }

    private func clearQueue() {
        queueRoots = []
        queue = []
        notice = nil
    }

    private func enqueue(_ mod: CatalogMod, selected: ModRelease? = nil) {
        perform {
            let release: ModRelease
            if let selected { release = selected }
            else { release = try await catalog.latest(mod) }
            let roots = queueRoots.filter { $0.id != mod.id } + [QueuedMod(project: mod, release: release)]
            let resolved = try await catalog.dependencyQueue(for: roots)
            queueRoots = roots
            queue = resolved
            notice = "「\(mod.name)」をキューに追加しました。"
        }
    }

    private func downloadQueue() {
        perform {
            var count = 0
            for item in queue {
                if try await install(item.project, release: item.release) { count += 1 }
            }
            queue = []
            queueRoots = []
            notice = count == 0 ? "対象のModはすでに導入済みです。" : "\(count)件のModをダウンロードしました。"
        }
    }

    @ViewBuilder private var feedback: some View {
        if busy { ProgressView() }
        if let notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
    }

    @MainActor
    private func search(_ input: SearchInput) async {
        guard !Task.isCancelled, input == searchInput else { return }
        let requestID = UUID()
        activeSearchID = requestID
        searching = true
        searchNotice = nil
        nextOffset = nil
        failedOffset = nil
        results = []
        defer {
            if activeSearchID == requestID { searching = false }
        }
        do {
            if !input.query.isEmpty || input.provider == .curseForge {
                try await Task.sleep(for: .milliseconds(300))
            }
            let source = ModCatalog(instance: instance, curseForgeKey: input.key)
            let matches = try await source.search(input.query, provider: input.provider)
            try Task.checkCancellation()
            guard activeSearchID == requestID, input == searchInput else { return }
            results = matches
            nextOffset = matches.count == ModCatalog.searchPageSize ? matches.count : nil
            if matches.isEmpty { searchNotice = "対応するModが見つかりませんでした。" }
        } catch {
            guard !Task.isCancelled, activeSearchID == requestID, input == searchInput else { return }
            searchNotice = error.localizedDescription
        }
    }

    @MainActor
    private func loadNextPage(_ input: SearchInput, offset: Int) async {
        guard !Task.isCancelled, input == searchInput, nextOffset == offset else { return }
        let requestID = activeSearchID
        do {
            let source = ModCatalog(instance: instance, curseForgeKey: input.key)
            let matches = try await source.search(input.query, provider: input.provider, offset: offset)
            try Task.checkCancellation()
            guard activeSearchID == requestID, input == searchInput, nextOffset == offset else { return }
            var ids = Set(results.map(\.id))
            let unique = matches.filter { ids.insert($0.id).inserted }
            results.append(contentsOf: unique)
            nextOffset = matches.count == ModCatalog.searchPageSize && !unique.isEmpty ? offset + matches.count : nil
            searchNotice = nil
        } catch {
            guard !Task.isCancelled, activeSearchID == requestID, input == searchInput else { return }
            nextOffset = nil
            failedOffset = offset
            searchNotice = error.localizedDescription
        }
    }

    private func download(_ mod: CatalogMod) {
        perform {
            let release = try await catalog.latest(mod)
            let plan = try await catalog.dependencyQueue(for: [QueuedMod(project: mod, release: release)])
            var changed = false
            for item in plan {
                if try await install(item.project, release: item.release) { changed = true }
            }
            notice = changed ? "Modを更新しました。" : "最新版です。"
        }
    }

    private func toggleInstalled(_ item: InstalledMod) {
        guard let index = installed.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = installed
        perform {
            let root = try directory()
            let original = updated[index]
            let filename = original.isDisabled
                ? String(original.file.dropLast(".disabled".count))
                : original.file + ".disabled"
            let source = root.appending(path: original.file)
            let target = root.appending(path: filename)
            try FileManager.default.moveItem(at: source, to: target)
            updated[index].disabled = !original.isDisabled
            updated[index].file = filename
            do {
                try saveManifest(updated, in: root)
            } catch {
                try FileManager.default.moveItem(at: target, to: source)
                throw error
            }
        }
    }

    private func deleteInstalled(_ item: InstalledMod) {
        perform {
            let root = try directory()
            let file = root.appending(path: item.file)
            let staged = root.appending(path: UUID().uuidString + ".removed")
            let files = FileManager.default
            let exists = files.fileExists(atPath: file.path)
            if exists { try files.moveItem(at: file, to: staged) }
            do {
                try saveManifest(installed.filter { $0.id != item.id }, in: root)
            } catch {
                if exists { try files.moveItem(at: staged, to: file) }
                throw error
            }
            if exists { try files.removeItem(at: staged) }
        }
    }

    private func saveManifest(_ items: [InstalledMod], in root: URL) throws {
        try JSONEncoder().encode(items).write(to: root.appending(path: ".amethyst-mods.json"), options: .atomic)
        installed = items
    }

    private func install(_ mod: CatalogMod, release: ModRelease) async throws -> Bool {
        let previous = installed.first { $0.id == mod.id }
        if previous?.releaseID == release.id,
           let previous, FileManager.default.fileExists(atPath: try directory().appending(path: previous.file).path) {
            return false
        }
        guard release.url.scheme == "https" else { throw CatalogError.invalidFile }
        let root = try directory()
        let filename = UUID().uuidString + ".jar" + (previous?.isDisabled == true ? ".disabled" : "")
        let destination = root.appending(path: filename)
        let (temporary, response) = try await URLSession.shared.download(from: release.url)
        try ModCatalog.check(response)
        let handle = try FileHandle(forReadingFrom: temporary)
        defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data([0x50, 0x4b, 0x03, 0x04]) else {
            throw CatalogError.invalidFile
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        let record = InstalledMod(project: mod, releaseID: release.id, version: release.name, file: filename, disabled: previous?.disabled)
        let updated = installed.filter { $0.id != mod.id } + [record]
        do {
            try saveManifest(updated, in: root)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        if let previous { try? FileManager.default.removeItem(at: root.appending(path: previous.file)) }
        return true
    }


    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        notice = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await action() }
            catch { notice = error.localizedDescription }
        }
    }

    private func directory() throws -> URL {
        let root = gameDirectory.appending(path: "mods")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}


@available(iOS 17.0, *)
private struct ModStatusIcons: View {
    let installed: Bool
    let queued: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .opacity(installed ? 1 : 0)
                .accessibilityLabel("ダウンロード済み")
                .accessibilityHidden(!installed)
            Image(systemName: "tray.and.arrow.down.fill")
                .foregroundStyle(Color.accentColor)
                .opacity(queued ? 1 : 0)
                .accessibilityLabel("キューに追加済み")
                .accessibilityHidden(!queued)
        }
        .font(.caption)
        .lineLimit(1)
    }
}
