import UIKit
import PhotosUI

final class ProfileEditViewController: UIViewController, PHPickerViewControllerDelegate, UITextFieldDelegate {
    private let nameField = UITextField()
    private let imageView = UIImageView()
    private let pickButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let stack = UIStackView()
    private let api = APIClient()

    private var selectedImageData: Data?
    private var selectedMime: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "プロフィール設定"
        view.backgroundColor = .systemBackground
        setupUI()
    }

    private func setupUI() {
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        nameField.placeholder = "表示名（必須）"
        nameField.borderStyle = .roundedRect
        nameField.delegate = self

        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .secondarySystemBackground
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.heightAnchor.constraint(equalToConstant: 160).isActive = true

        pickButton.setTitle("アイコン画像を選択", for: .normal)
        pickButton.addTarget(self, action: #selector(tapPick), for: .touchUpInside)

        saveButton.setTitle("保存", for: .normal)
        saveButton.addTarget(self, action: #selector(tapSave), for: .touchUpInside)
        saveButton.titleLabel?.font = .boldSystemFont(ofSize: 16)

        [nameField, imageView, pickButton, saveButton].forEach { stack.addArrangedSubview($0) }
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])
    }

    @objc private func tapPick() {
        var conf = PHPickerConfiguration()
        conf.selectionLimit = 1
        conf.filter = .images
        let picker = PHPickerViewController(configuration: conf)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        guard let item = results.first else { return }
        if item.itemProvider.hasItemConformingToTypeIdentifier("public.heic") {
            loadImage(item: item, preferredUTType: "public.heic", mime: "image/heic")
        } else if item.itemProvider.hasItemConformingToTypeIdentifier("public.jpeg") {
            loadImage(item: item, preferredUTType: "public.jpeg", mime: "image/jpeg")
        } else if item.itemProvider.hasItemConformingToTypeIdentifier("public.png") {
            loadImage(item: item, preferredUTType: "public.png", mime: "image/png")
        } else {
            // fallback to image
            item.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let self, let img = object as? UIImage, let data = img.jpegData(compressionQuality: 0.9) else { return }
                DispatchQueue.main.async {
                    self.imageView.image = img
                    self.selectedImageData = data
                    self.selectedMime = "image/jpeg"
                }
            }
        }
    }

    private func loadImage(item: PHPickerResult, preferredUTType: String, mime: String) {
        item.itemProvider.loadDataRepresentation(forTypeIdentifier: preferredUTType) { [weak self] data, _ in
            guard let self, let data else { return }
            DispatchQueue.main.async {
                self.imageView.image = UIImage(data: data)
                self.selectedImageData = data
                self.selectedMime = (mime == "image/heic") ? "image/jpeg" : mime // 互換性のためHEICはJPEG保存
            }
        }
    }

    @objc private func tapSave() {
        let name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { alert("入力エラー", "表示名を入力してください"); return }

        Task { @MainActor in
            saveButton.isEnabled = false
            defer { saveButton.isEnabled = true }
            do {
                var avatarPath: String? = nil
                if let data = selectedImageData, let mime = selectedMime {
                    // 1) 署名付きアップロードURLを取得
                    let ext = mime.contains("png") ? "png" : "jpeg"
                    let up = try await api.profileAvatarUploadURL(ext: ext)
                    // 2) 画像をアップロード
                    try await api.profileAvatarUpload(to: up.uploadUrl, data: data, mime: mime)
                    avatarPath = up.path
                }
                // 3) commit
                try await api.profileAvatarCommit(path: avatarPath, name: name)
                alert("保存しました", "プロフィールを更新しました。") { [weak self] in self?.navigationController?.popViewController(animated: true) }
            } catch {
                alert("保存に失敗", error.localizedDescription)
            }
        }
    }

    private func alert(_ title: String, _ msg: String, completion: (() -> Void)? = nil) {
        let a = UIAlertController(title: title, message: msg, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in completion?() }))
        present(a, animated: true)
    }
}
