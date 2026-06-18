import Foundation

enum VaultState: Equatable {
    case missing
    case locked
    case unlocked(mountPoint: URL)
    case working(String)
    case error(String)

    var isMounted: Bool {
        if case .unlocked = self {
            return true
        }
        return false
    }

    var isWorking: Bool {
        if case .working = self {
            return true
        }
        return false
    }

    var title: String {
        switch self {
        case .missing:
            return "No vault yet"
        case .locked:
            return "Locked"
        case .unlocked:
            return "Unlocked"
        case .working(let label):
            return label
        case .error:
            return "Needs attention"
        }
    }
}

struct VaultItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let kind: String
    let sizeDescription: String
    let addedAt: Date
}

struct VaultEvent: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let title: String
    let detail: String
}
