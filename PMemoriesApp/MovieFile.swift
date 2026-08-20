import CoreTransferable
import UniformTypeIdentifiers

/// PhotosPickerItem nie ma wbudowanego Transferable dla wideo — plik
/// dostarczony w importing: jest ważny tylko w trakcie closure, więc trzeba
/// go skopiować do stabilnej lokalizacji tymczasowej.
struct MovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}
