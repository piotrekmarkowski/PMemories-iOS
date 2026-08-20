import SwiftUI
import MediaPlayer

/// Wrapper na MPMediaPickerController — SwiftUI nie ma natywnego pickera muzyki.
struct MusicPicker: UIViewControllerRepresentable {
    var onPick: (MPMediaItem) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = false
        picker.showsCloudItems = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: MPMediaPickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        let onPick: (MPMediaItem) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (MPMediaItem) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
            if let item = mediaItemCollection.items.first {
                onPick(item)
            } else {
                onCancel()
            }
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            onCancel()
        }
    }
}
