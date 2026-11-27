import Foundation

enum InstanceLoader: String, Codable, CaseIterable, Identifiable {
    case vanilla = "Vanilla"
    case fabric = "Fabric"
    case quilt = "Quilt"
    case forge = "Forge"
    case neoForge = "NeoForge"

    var id: String { rawValue }
}

enum InstanceArtwork: String, Codable, CaseIterable, Identifiable {
    case meadow = "草地"
    case ocean = "海"
    case ember = "溶岩"
    case amethyst = "アメジスト"

    var id: String { rawValue }
}

struct LauncherInstance: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var version: String
    var loader: InstanceLoader
    var group: String
    var artwork: InstanceArtwork?

    var displayArtwork: InstanceArtwork {
        artwork ?? (loader == .vanilla ? .meadow : .amethyst)
    }

}
