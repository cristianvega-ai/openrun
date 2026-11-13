import AppKit

/// What the composer does with images and with a held message.
extension ComposerView {
    func connectImages() {
        textView.imagesAction = { [weak self] data in self?.addImages(data) }
        previews.removeAction = { [weak self] index in
            guard let self, images.indices.contains(index) else { return }
            images.remove(at: index)
            draftChanged?(draft)
            refresh()
        }
        heldView.editAction = { [weak self] in self?.takeHeldMessage() }
        heldView.deleteAction = { [weak self] in
            _ = self?.logic.takeHeldMessage()
            if let self { self.draftChanged?(self.draft) }
            self?.refresh()
        }
    }

    /// Adds the images that can go, and tells why another one cannot.
    func addImages(_ data: [Data]) {
        problem = nil
        for item in data {
            switch ComposerImage.image(from: item) {
            case .success(let image): images.append(image)
            case .failure(let failure): problem = failure.message
            }
        }
        draftChanged?(draft)
        refresh()
    }

    /// Puts a held message back in the field, so the user can change it.
    @objc func takeHeldMessage() {
        guard let held = logic.takeHeldMessage() else { return }
        textView.string = held.text + (textView.string.isEmpty ? "" : "\n\n" + textView.string)
        images = held.images + images
        draftChanged?(draft)
        refresh()
    }
}
