import Foundation

enum ModProvider: String, Codable, CaseIterable, Identifiable {
    case modrinth = "Modrinth"
    case curseForge = "CurseForge"
    var id: String { rawValue }
}

struct CatalogMod: Identifiable, Codable {
    let provider: ModProvider
    let projectID: String
    let name: String
    let summary: String
    var iconURL: URL? = nil
    var id: String { provider.rawValue + "-" + projectID }
}

struct ModRelease {
    let id: String
    let name: String
    let url: URL
    var dependencies: [ModDependency] = []
}

struct ModDependency {
    let projectID: String?
    let releaseID: String?
}

struct QueuedMod: Identifiable {
    let project: CatalogMod
    let release: ModRelease
    var id: String { project.id }
}

struct InstalledMod: Identifiable, Codable {
    let project: CatalogMod
    let releaseID: String
    let version: String
    var file: String
    var disabled: Bool?
    var isDisabled: Bool { disabled == true }
    var id: String { project.id }
}

enum CatalogError: LocalizedError {
    case request(Int), keyRequired, unavailable, restricted, invalidFile, dependencyConflict(String)

    var errorDescription: String? {
        switch self {
        case .request(let status): "通信に失敗しました（HTTP \(status)）。"
        case .keyRequired: "CurseForgeのAPIキーを入力してください。"
        case .unavailable: "このMinecraftバージョンとローダーに対応するファイルがありません。"
        case .restricted: "配布元がAPI経由でのダウンロードを提供していません。"
        case .dependencyConflict(let name): "「\(name)」に異なるバージョンが必要です。キューの構成を確認してください。"
        case .invalidFile: "有効なJARファイルを取得できませんでした。"
        }
    }
}

struct ModCatalog {
    let instance: LauncherInstance
    let curseForgeKey: String

    private var loader: String { instance.loader.rawValue.lowercased() }
    private var curseLoader: String {
        switch instance.loader {
        case .vanilla: "0"
        case .forge: "1"
        case .fabric: "4"
        case .quilt: "5"
        case .neoForge: "6"
        }
    }

    static let searchPageSize = 25

    func search(_ query: String, provider: ModProvider, offset: Int = 0) async throws -> [CatalogMod] {
        switch provider {
        case .modrinth:
            let facets = [["project_type:mod"], ["versions:\(instance.version)"], ["categories:\(loader)"]]
            let result: ModrinthSearch = try await fetch(provider, path: "/v2/search", query: [
                "query": query, "facets": try json(facets), "limit": String(Self.searchPageSize), "offset": String(offset)
            ])
            return result.hits.map {
                CatalogMod(provider: provider, projectID: $0.project_id, name: $0.title, summary: $0.description, iconURL: Self.imageURL($0.icon_url))
            }
        case .curseForge:
            let result: CurseResponse<[CurseProject]> = try await fetch(provider, path: "/v1/mods/search", query: [
                "gameId": "432", "classId": "6", "gameVersion": instance.version,
                "modLoaderType": curseLoader, "searchFilter": query, "pageSize": String(Self.searchPageSize), "index": String(offset)
            ])
            return result.data.map {
                CatalogMod(provider: provider, projectID: String($0.id), name: $0.name, summary: $0.summary, iconURL: Self.imageURL($0.logo?.thumbnailUrl) ?? Self.imageURL($0.logo?.url))
            }
        }
    }

    func latest(_ mod: CatalogMod) async throws -> ModRelease {
        let available = try await releases(mod, latestOnly: true)
        guard let first = available.first else { throw CatalogError.unavailable }
        return first
    }

    func releases(_ mod: CatalogMod, latestOnly: Bool = false) async throws -> [ModRelease] {
        switch mod.provider {
        case .modrinth:
            let versions: [ModrinthVersion] = try await fetch(mod.provider,
                path: "/v2/project/\(mod.projectID)/version",
                query: ["game_versions": try json([instance.version]), "loaders": try json([loader])])
            let available = versions.sorted { $0.date_published > $1.date_published }.compactMap { version -> ModRelease? in
                let jars = version.files.filter { $0.filename.lowercased().hasSuffix(".jar") }
                guard let file = jars.first(where: \.primary) ?? jars.first else { return nil }
                return ModRelease(id: version.id, name: version.version_number, url: file.url,
                                  dependencies: version.dependencies.filter { $0.dependency_type == "required" }
                                      .map { ModDependency(projectID: $0.project_id, releaseID: $0.version_id) })
            }
            guard !available.isEmpty else { throw CatalogError.unavailable }
            return available
        case .curseForge:
            let result: CurseResponse<[CurseFile]> = try await fetch(mod.provider,
                path: "/v1/mods/\(mod.projectID)/files",
                query: ["gameVersion": instance.version, "modLoaderType": curseLoader, "pageSize": "50"])
            let jars = result.data.filter { $0.fileName.lowercased().hasSuffix(".jar") }
                .sorted { $0.fileDate > $1.fileDate }
            guard let newest = jars.first else { throw CatalogError.unavailable }
            let candidates = latestOnly ? [newest] : jars
            let available = candidates.compactMap { file -> ModRelease? in
                guard let url = file.downloadUrl else { return nil }
                return ModRelease(id: String(file.id), name: file.displayName, url: url,
                                  dependencies: (file.dependencies ?? []).filter { $0.relationType == 3 }
                                      .map { ModDependency(projectID: String($0.modId), releaseID: $0.fileId.flatMap { $0 > 0 ? String($0) : nil }) })
            }
            guard !available.isEmpty else { throw CatalogError.restricted }
            return available
        }
    }

    func dependencyQueue(for roots: [QueuedMod]) async throws -> [QueuedMod] {
        var chosen: [String: QueuedMod] = [:]
        for root in roots { chosen[root.id] = root }
        var visited: Set<String> = []
        var ordered: [QueuedMod] = []

        func visit(_ item: QueuedMod) async throws {
            guard visited.insert(item.id).inserted else { return }
            for dependency in item.release.dependencies {
                let provider = item.project.provider
                var projectID = dependency.projectID
                if projectID == nil, let version = dependency.releaseID, provider == .modrinth {
                    let info: ModrinthVersion = try await fetch(provider, path: "/v2/version/\(version)", query: [:])
                    projectID = info.project_id
                }
                guard let projectID else { throw CatalogError.unavailable }
                let id = provider.rawValue + "-" + projectID
                if let existing = chosen[id] {
                    if let releaseID = dependency.releaseID, existing.release.id != releaseID {
                        throw CatalogError.dependencyConflict(existing.project.name)
                    }
                    try await visit(existing)
                    continue
                }
                let project = try await projectInfo(provider, id: projectID)
                let release: ModRelease
                if let releaseID = dependency.releaseID {
                    let available = try await releases(project)
                    guard let pinned = available.first(where: { $0.id == releaseID }) else {
                        throw CatalogError.unavailable
                    }
                    release = pinned
                } else {
                    release = try await latest(project)
                }
                let child = QueuedMod(project: project, release: release)
                chosen[id] = child
                try await visit(child)
            }
            ordered.append(item)
        }

        for root in roots { try await visit(root) }
        return ordered
    }

    private func projectInfo(_ provider: ModProvider, id: String) async throws -> CatalogMod {
        switch provider {
        case .modrinth:
            let project: ModrinthProject = try await fetch(provider, path: "/v2/project/\(id)", query: [:])
            return CatalogMod(provider: provider, projectID: project.id, name: project.title,
                              summary: project.description, iconURL: Self.imageURL(project.icon_url))
        case .curseForge:
            let result: CurseResponse<CurseProject> = try await fetch(provider, path: "/v1/mods/\(id)", query: [:])
            let project = result.data
            return CatalogMod(provider: provider, projectID: String(project.id), name: project.name,
                              summary: project.summary, iconURL: Self.imageURL(project.logo?.thumbnailUrl) ?? Self.imageURL(project.logo?.url))
        }
    }

    private func fetch<T: Decodable>(_ provider: ModProvider, path: String, query: [String: String]) async throws -> T {
        var url = URLComponents()
        url.scheme = "https"
        url.host = provider == .modrinth ? "api.modrinth.com" : "api.curseforge.com"
        url.path = path
        url.queryItems = query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let endpoint = url.url else { throw CatalogError.unavailable }
        var request = URLRequest(url: endpoint)
        request.setValue("LauncherUI/0.1 (Amethyst UI prototype)", forHTTPHeaderField: "User-Agent")
        if provider == .curseForge {
            let key = curseForgeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw CatalogError.keyRequired }
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    private static func imageURL(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    static func check(_ response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw CatalogError.request(status) }
    }
}

private struct ModrinthSearch: Decodable {
    struct Hit: Decodable { let project_id, title, description: String; let icon_url: String? }
    let hits: [Hit]
}
private struct ModrinthProject: Decodable {
    let id, title, description: String
    let icon_url: String?
}
private struct ModrinthVersion: Decodable {
    struct File: Decodable { let url: URL; let filename: String; let primary: Bool }
    let id, version_number, date_published: String
    struct Dependency: Decodable {
        let project_id, version_id: String?
        let dependency_type: String
    }
    let project_id: String
    let files: [File]
    let dependencies: [Dependency]
}
private struct CurseResponse<T: Decodable>: Decodable { let data: T }
private struct CurseProject: Decodable {
    struct Logo: Decodable { let thumbnailUrl, url: String? }
    let id: Int
    let name, summary: String
    let logo: Logo?
}
private struct CurseFile: Decodable {
    let id: Int
    let displayName, fileName, fileDate: String
    struct Dependency: Decodable {
        let modId, relationType: Int
        let fileId: Int?
    }
    let dependencies: [Dependency]?
    let downloadUrl: URL?
}
