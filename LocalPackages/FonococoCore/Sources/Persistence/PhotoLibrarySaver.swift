import Photos
import UIKit

@MainActor
public final class PhotoLibrarySaver: NSObject {
    public enum SaveError: LocalizedError {
        case denied, missingUsageDescription, alreadySaving
        public var errorDescription: String? {
            switch self {
            case .denied: return "No se permitió guardar en Fotos."
            case .missingUsageDescription: return "Falta NSPhotoLibraryAddUsageDescription."
            case .alreadySaving: return "Ya hay una imagen guardándose."
            }
        }
    }
    private var continuation: CheckedContinuation<Void, Error>?
    // UIImageWriteToSavedPhotosAlbum does not provide an ownership guarantee for its callback target.
    private var retainedUntilCompletion: PhotoLibrarySaver?
    public func save(_ image: UIImage) async throws {
        guard continuation == nil else { throw SaveError.alreadySaving }
        guard let usage = Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription") as? String,
              !usage.isEmpty else { throw SaveError.missingUsageDescription }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }
        guard continuation == nil else { throw SaveError.alreadySaving }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            retainedUntilCompletion = self
            UIImageWriteToSavedPhotosAlbum(image, self, #selector(completed(_:didFinishSavingWithError:contextInfo:)), nil)
        }
    }
    @objc private func completed(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeMutableRawPointer?) {
        let pending = continuation
        continuation = nil
        retainedUntilCompletion = nil
        if let error { pending?.resume(throwing: error) }
        else { pending?.resume() }
    }
}
