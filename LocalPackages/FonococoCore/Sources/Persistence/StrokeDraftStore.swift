import CoreData
import Foundation

/// Native PencilKit data is backed up independently of the completed-album store.
public final class StrokeDraftStore {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    private init(container: NSPersistentContainer) {
        self.container = container
        context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    public static func make(storeURL: URL) async throws -> StrokeDraftStore {
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "StrokeDraft"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        let attributes: [(String, NSAttributeType)] = [
            ("roomID", .stringAttributeType), ("turnID", .stringAttributeType),
            ("data", .binaryDataAttributeType), ("updatedAt", .dateAttributeType)
        ]
        entity.properties = attributes.map { name, type in
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = type
            attribute.isOptional = false
            return attribute
        }
        entity.uniquenessConstraints = [["roomID", "turnID"]]
        model.entities = [entity]
        let container = NSPersistentContainer(name: "StrokeDrafts", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        return StrokeDraftStore(container: container)
    }

    public func save(roomID: String, turnID: String, data: Data) async throws {
        try await context.perform { [context] in
            let request = Self.request(roomID: roomID, turnID: turnID)
            do {
                let draft = try context.fetch(request).first ?? NSEntityDescription.insertNewObject(forEntityName: "StrokeDraft", into: context)
                draft.setValue(roomID, forKey: "roomID")
                draft.setValue(turnID, forKey: "turnID")
                draft.setValue(data, forKey: "data")
                draft.setValue(Date(), forKey: "updatedAt")
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func load(roomID: String, turnID: String) async throws -> Data? {
        try await context.perform { [context] in
            try context.fetch(Self.request(roomID: roomID, turnID: turnID)).first?.value(forKey: "data") as? Data
        }
    }

    public func remove(roomID: String, turnID: String) async throws {
        try await context.perform { [context] in
            do {
                for object in try context.fetch(Self.request(roomID: roomID, turnID: turnID)) { context.delete(object) }
                try context.save()
            } catch { context.rollback(); throw error }
        }
    }

    private static func request(roomID: String, turnID: String) -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "StrokeDraft")
        request.predicate = NSPredicate(format: "roomID == %@ AND turnID == %@", roomID, turnID)
        request.fetchLimit = 1
        return request
    }
}
