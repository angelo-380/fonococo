import Foundation
import SwiftData

@Model
public final class ArchivedAlbum {
    @Attribute(.unique) public var id: String
    public var title: String
    public var completedAt: Date
    @Attribute(.externalStorage) public var payload: Data

    public init(id: String, title: String, completedAt: Date = .now, payload: Data) {
        self.id = id
        self.title = title
        self.completedAt = completedAt
        self.payload = payload
    }

    public func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
        try JSONDecoder().decode(type, from: payload)
    }
}

@MainActor
public final class AlbumRepository {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    public func save(id: String, title: String, payload: Data) throws {
        let selectedID = id
        let descriptor = FetchDescriptor<ArchivedAlbum>(predicate: #Predicate { $0.id == selectedID })
        do {
            if let existing = try context.fetch(descriptor).first {
                existing.title = title
                existing.payload = payload
            } else {
                context.insert(ArchivedAlbum(id: id, title: title, payload: payload))
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
