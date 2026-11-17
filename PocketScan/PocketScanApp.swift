import SwiftUI
import UIKit
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins

@main
struct PocketScanApp: App {
    @StateObject private var store = ScanStore()
    var body: some Scene {
        WindowGroup { HomeView().environmentObject(store).tint(.teal) }
    }
}

struct ScanDoc: Identifiable, Codable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    var pages: [ScanPage] = []
}
struct ScanFilterPreset: Identifiable {
    let id: Int
    let name: String
    let description: String

    static let all: [ScanFilterPreset] = [
        .init(id: 0, name: "원본", description: "보정하지 않은 사진"),
        .init(id: 1, name: "문서 선명", description: "글자와 색상 또렷하게"),
        .init(id: 2, name: "회색", description: "깔끔한 회색조"),
        .init(id: 3, name: "흑백", description: "진한 흑백 인쇄 느낌"),
        .init(id: 4, name: "고대비", description: "글자 대비 강화"),
        .init(id: 5, name: "밝은 문서", description: "어두운 종이를 밝게"),
        .init(id: 6, name: "그림자 완화", description: "그늘진 부분을 밝게"),
        .init(id: 7, name: "잉크 강조", description: "검은 글씨를 더 진하게"),
        .init(id: 8, name: "컬러 강화", description: "사진과 컬러 문서"),
        .init(id: 9, name: "부드럽게", description: "대비와 채도를 낮춤"),
        .init(id: 10, name: "따뜻한 색감", description: "은은한 온기"),
        .init(id: 11, name: "차가운 색감", description: "시원하고 차분하게"),
        .init(id: 12, name: "세피아", description: "빈티지 종이 느낌")
    ]

    static func name(for id: Int) -> String {
        all.first(where: { $0.id == id })?.name ?? "원본"
    }
}

/// The same processing pipeline is used for thumbnails and PDF exports.
enum ScanFilterEngine {
    static func render(_ original: UIImage, preset: Int) -> UIImage {
        guard preset != 0, var ci = CIImage(image: original) else { return original }

        func controls(_ contrast: Float = 1, _ saturation: Float = 1, _ brightness: Float = 0) {
            let f = CIFilter.colorControls()
            f.inputImage = ci
            f.contrast = contrast
            f.saturation = saturation
            f.brightness = brightness
            ci = f.outputImage ?? ci
        }
        func sharpen(_ amount: Float) {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = ci
            f.sharpness = amount
            ci = f.outputImage ?? ci
        }

        switch preset {
        case 1:
            controls(1.28, 1.08, 0.03)
            sharpen(0.40)
        case 2:
            controls(1.0, 0, 0)
        case 3:
            let f = CIFilter.photoEffectNoir()
            f.inputImage = ci
            ci = f.outputImage ?? ci
        case 4:
            controls(1.65, 0, -0.02)
        case 5:
            controls(1.16, 0.92, 0.12)
        case 6:
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = ci
            f.shadowAmount = 0.85
            f.highlightAmount = 1.0
            ci = f.outputImage ?? ci
            controls(1.07, 0.98, 0.03)
        case 7:
            controls(1.54, 0.12, -0.035)
            sharpen(0.65)
        case 8:
            controls(1.14, 1.28, 0.02)
            sharpen(0.30)
        case 9:
            controls(0.85, 0.86, 0.045)
        case 10:
            let f = CIFilter.sepiaTone()
            f.inputImage = ci
            f.intensity = 0.26
            ci = f.outputImage ?? ci
        case 11:
            let f = CIFilter(name: "CITemperatureAndTint", parameters: [
                kCIInputImageKey: ci,
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 7900, y: 0)
            ])
            ci = f?.outputImage ?? ci
        case 12:
            let f = CIFilter.sepiaTone()
            f.inputImage = ci
            f.intensity = 0.86
            ci = f.outputImage ?? ci
        default:
            return original
        }

        guard let rendered = CIContext().createCGImage(ci, from: ci.extent) else { return original }
        return UIImage(cgImage: rendered, scale: original.scale, orientation: .up)
    }
}

struct ScanPage: Identifiable, Codable {
    var id = UUID()
    var file: String
    var rotation = 0
    var filter = 0
}

@MainActor
final class ScanStore: ObservableObject {
    @Published var docs: [ScanDoc] = []
    let folder: URL
    private let record: URL
    init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PocketScan", isDirectory: true)
        record = folder.appendingPathComponent("documents.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: record), let saved = try? JSONDecoder().decode([ScanDoc].self, from: data) { docs = saved }
    }
    func save() {
        if let data = try? JSONEncoder().encode(docs) { try? data.write(to: record, options: .atomic) }
    }
    func newDocument(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        var doc = ScanDoc(title: "스캔 \(Date.now.formatted(date: .abbreviated, time: .shortened))")
        append(images, to: &doc)
        docs.insert(doc, at: 0); save()
    }
    func append(_ images: [UIImage], to doc: inout ScanDoc) {
        for image in images {
            let file = UUID().uuidString + ".jpg"
            if let data = image.jpegData(compressionQuality: 0.87) {
                do { try data.write(to: folder.appendingPathComponent(file), options: .atomic); doc.pages.append(ScanPage(file: file)) }
                catch { print("Unable to save scan:", error) }
            }
        }
    }
    func change(_ doc: ScanDoc) {
        guard let i = docs.firstIndex(where: { $0.id == doc.id }) else { return }
        docs[i] = doc; save()
    }
    func remove(_ doc: ScanDoc) {
        for p in doc.pages { try? FileManager.default.removeItem(at: folder.appendingPathComponent(p.file)) }
        docs.removeAll { $0.id == doc.id }; save()
    }
    func previewSource(_ page: ScanPage) -> UIImage? {
        guard let original = UIImage(contentsOfFile: folder.appendingPathComponent(page.file).path),
              original.size.width > 0, original.size.height > 0 else { return nil }
        let scale = min(1, 220 / max(original.size.width, original.size.height))
        let size = CGSize(width: original.size.width * scale, height: original.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            original.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    func image(_ page: ScanPage) -> UIImage? {
        guard let original = UIImage(contentsOfFile: folder.appendingPathComponent(page.file).path) else { return nil }
        var output = ScanFilterEngine.render(original, preset: page.filter)
        if page.rotation != 0 {
            let angle = CGFloat(page.rotation) * .pi / 180
            let canvas = CGRect(origin: .zero, size: output.size)
                .applying(CGAffineTransform(rotationAngle: angle)).standardized.size
            let format = UIGraphicsImageRendererFormat()
            format.scale = output.scale
            let source = output
            output = UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
                ctx.cgContext.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                ctx.cgContext.rotate(by: angle)
                source.draw(in: CGRect(x: -source.size.width / 2,
                                       y: -source.size.height / 2,
                                       width: source.size.width, height: source.size.height))
            }
        }
        return output
    }
    func pdf(_ doc: ScanDoc) -> URL? {
        guard !doc.pages.isEmpty else { return nil }
        let size = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let data = UIGraphicsPDFRenderer(bounds: size).pdfData { renderer in
            for page in doc.pages {
                guard let image = image(page), image.size.width > 0, image.size.height > 0 else { continue }
                renderer.beginPage()
                let area = size.insetBy(dx: 20, dy: 20)
                let ratio = min(area.width / image.size.width, area.height / image.size.height)
                let w = image.size.width * ratio, h = image.size.height * ratio
                image.draw(in: CGRect(x: area.midX - w/2, y: area.midY - h/2, width: w, height: h))
            }
        }
        let name = doc.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + "-" + UUID().uuidString.prefix(5) + ".pdf")
        do { try data.write(to: url); return url } catch { return nil }
    }
}


/** Standard iPhone camera with a manual shutter. No auto capture or auto cropping. */
struct ScanCamera: UIViewControllerRepresentable {
    var complete: ([UIImage]) -> Void
    var cancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.showsCameraControls = true
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        return picker
    }
    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ScanCamera
        init(_ parent: ScanCamera) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else {
                parent.cancel()
                return
            }
            parent.complete([image])
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.cancel()
        }
    }
}

struct SharePDF: Identifiable { let id = UUID(); let url: URL }
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


private struct SuccessfulBuilds: Decodable {
    let workflow_runs: [SuccessfulBuild]
}
private struct SuccessfulBuild: Decodable {
    let head_sha: String
    let html_url: String
}

@MainActor
final class GitHubUpdateChecker: ObservableObject {
    @Published var checking = false
    @Published var showResult = false
    @Published var hasUpdate = false
    @Published var message = ""

    var installedRevision: String {
        (Bundle.main.object(forInfoDictionaryKey: "PocketScanBuildSHA") as? String) ?? "unknown"
    }

    func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false; showResult = true }
        do {
            guard let url = URL(string: "https://api.github.com/repos/pullgena/pocketscan-native/actions/workflows/build-ipa.yml/runs?branch=main&status=success&per_page=1") else {
                message = "GitHub 주소가 올바르지 않습니다."
                return
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("PocketScan-iOS/1.2", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                message = "GitHub 서버에서 최신 버전을 가져오지 못했습니다. 잠시 후 다시 시도해 주세요."
                return
            }
            let builds = try JSONDecoder().decode(SuccessfulBuilds.self, from: data)
            guard let newest = builds.workflow_runs.first else {
                message = "GitHub에 성공한 IPA 빌드가 아직 없습니다."
                return
            }
            hasUpdate = (installedRevision != newest.head_sha)
            if hasUpdate {
                message = "GitHub에 새 IPA 빌드가 있습니다. '빌드 열기'를 눌러 IPA를 다운로드한 뒤 Windows의 Sideloadly에서 다시 설치해 주세요. iOS 앱이 자동으로 설치되지는 않습니다."
            } else {
                message = "현재 설치한 포켓스캔은 GitHub에서 빌드에 성공한 최신 버전입니다."
            }
        } catch {
            hasUpdate = false
            message = "업데이트를 확인할 수 없습니다. 인터넷 연결과 GitHub 접근 가능 여부를 확인해 주세요."
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var store: ScanStore
    @State private var camera = false
    @State private var selection: [PhotosPickerItem] = []
    @StateObject private var updates = GitHubUpdateChecker()
    @State private var cameraUnavailable = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("포켓스캔", systemImage: "doc.viewfinder").font(.largeTitle.bold()).foregroundStyle(.teal)
                        Text("서류부터 문제집까지, 간편하게 스캔하세요.").foregroundStyle(.secondary)
                    }.padding(.top)
                    Button { if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true } else { cameraUnavailable = true } } label: {
                        Label("새 문서 스캔", systemImage: "camera.viewfinder")
                            .font(.title3.bold()).frame(maxWidth: .infinity).padding(20)
                    }.buttonStyle(.borderedProminent).tint(.teal)
                    PhotosPicker(selection: $selection, maxSelectionCount: 30, matching: .images) {
                        Label("사진에서 불러오기", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity).padding(12)
                    }.buttonStyle(.bordered)

                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Label("GitHub 업데이트", systemImage: "arrow.triangle.2.circlepath")
                                .font(.headline)
                            Spacer()
                            Text("v1.2").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("GitHub에서 빌드에 성공한 새 IPA가 있는지 확인합니다.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button {
                            Task { await updates.check() }
                        } label: {
                            Label(updates.checking ? "확인하는 중..." : "업데이트 확인", systemImage: "arrow.down.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(updates.checking)
                        Text("새 IPA는 Windows에서 Sideloadly로 다시 설치해야 합니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    Text("내 문서").font(.title2.bold()).padding(.top)
                    if store.docs.isEmpty {
                        ContentUnavailableView("아직 스캔한 문서가 없습니다", systemImage: "doc.text.viewfinder", description: Text("카메라로 촬영하거나 사진을 가져오세요."))
                    }
                    ForEach(store.docs) { doc in
                        NavigationLink {
                            EditorView(docID: doc.id)
                        } label: {
                            HStack(spacing: 15) {
                                if let first = doc.pages.first, let image = store.image(first) {
                                    Image(uiImage: image).resizable().scaledToFill().frame(width: 65, height: 78).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                } else { Image(systemName: "doc").frame(width: 65, height: 78) }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(doc.title).font(.headline).foregroundStyle(.primary)
                                    Text("\(doc.pages.count)페이지 · \(doc.createdAt.formatted(date: .numeric, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }
                    Text("문서는 이 아이폰에만 저장됩니다. PDF로 내보내 백업할 수 있습니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .sheet(isPresented: $camera) {
                ScanCamera(complete: { images in
                    camera = false
                    store.newDocument(images)
                }, cancel: { camera = false }).ignoresSafeArea()
            }

            .alert("GitHub 업데이트 확인", isPresented: $updates.showResult) {
                if updates.hasUpdate {
                    Button("빌드 열기") {
                        if let url = URL(string: "https://github.com/pullgena/pocketscan-native/actions/workflows/build-ipa.yml") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Button("닫기", role: .cancel) {}
            } message: {
                Text(updates.message)
            }
            .alert("카메라를 열 수 없습니다", isPresented: $cameraUnavailable) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("이 기기에서는 카메라를 사용할 수 없습니다. 대신 사진을 불러와 주세요.")
            }
            .onChange(of: selection) { _, items in
                Task {
                    var images: [UIImage] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { images.append(image) }
                    }
                    store.newDocument(images)
                    selection = []
                }
            }
        }
    }
}

struct FilterPickerView: View {
    @EnvironmentObject private var store: ScanStore
    @Environment(\.dismiss) private var dismiss

    let page: ScanPage
    let onSelect: (Int) -> Void
    @State private var previews: [Int: UIImage] = [:]

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ScanFilterPreset.all) { preset in
                        Button {
                            onSelect(preset.id)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack(alignment: .topTrailing) {
                                    Group {
                                        if let thumbnail = previews[preset.id] {
                                            Image(uiImage: thumbnail)
                                                .resizable()
                                                .scaledToFit()
                                        } else {
                                            Image(systemName: "doc.text.image")
                                                .resizable()
                                                .scaledToFit()
                                                .padding(32)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 155)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                    if page.filter == preset.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(.teal)
                                            .padding(7)
                                    }
                                }
                                Text(preset.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text(preset.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(10)
                            .background(Color(uiColor: .secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 15))
                            .overlay(RoundedRectangle(cornerRadius: 15)
                                .stroke(page.filter == preset.id ? Color.teal : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("필터 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .onAppear {
                guard previews.isEmpty, let source = store.previewSource(page) else { return }
                for preset in ScanFilterPreset.all {
                    previews[preset.id] = ScanFilterEngine.render(source, preset: preset.id)
                }
            }
        }
    }
}

struct EditorView: View {
    @EnvironmentObject var store: ScanStore
    @Environment(\.dismiss) var dismiss
    let docID: UUID
    @State private var camera = false
    @State private var cameraUnavailable = false
    @State private var selection: [PhotosPickerItem] = []
    @State private var share: SharePDF?
    @State private var filterPage: ScanPage?
    @State private var rename = false
    @State private var title = ""
    private var doc: ScanDoc? { store.docs.first { $0.id == docID } }
    var body: some View {
        Group {
            if let doc {
                ScrollView {
                    VStack(spacing: 16) {
                        HStack {
                            Text(doc.title).font(.title2.bold())
                            Spacer()
                            Button("이름 변경") { title = doc.title; rename = true }
                        }
                        ForEach(Array(doc.pages.enumerated()), id: \.element.id) { index, page in
                            VStack(spacing: 12) {
                                if let image = store.image(page) {
                                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 360)
                                        .frame(maxWidth: .infinity).background(Color(uiColor: .secondarySystemGroupedBackground))
                                }
                                HStack {
                                    Text("\(index + 1) / \(doc.pages.count)").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button {
                                        filterPage = page
                                    } label: {
                                        Label(ScanFilterPreset.name(for: page.filter), systemImage: "slider.horizontal.3")
                                    }
                                    Button { editPage(page.id) { $0.rotation = ($0.rotation + 90) % 360 } } label: { Image(systemName: "rotate.right") }
                                    Button { move(index, -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0)
                                    Button { move(index, 1) } label: { Image(systemName: "arrow.down") }.disabled(index + 1 >= doc.pages.count)
                                    Button(role: .destructive) { delete(page.id) } label: { Image(systemName: "trash") }
                                }.buttonStyle(.borderless).font(.subheadline)
                            }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                        Button {
                            if let url = store.pdf(doc) { share = SharePDF(url: url) }
                        } label: {
                            Label("PDF 만들기 · 파일에 저장", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity).padding(12)
                        }.buttonStyle(.borderedProminent).tint(.teal).disabled(doc.pages.isEmpty)
                        Button(role: .destructive) {
                            store.remove(doc)
                            dismiss()
                        } label: { Label("문서 삭제", systemImage: "trash") }
                    }.padding()
                }
                .background(Color(uiColor: .systemGroupedBackground))
            } else { ContentUnavailableView("문서를 찾을 수 없습니다", systemImage: "doc") }
        }
        .navigationTitle("문서 편집").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true } else { cameraUnavailable = true } } label: { Image(systemName: "camera") }
                PhotosPicker(selection: $selection, maxSelectionCount: 30, matching: .images) { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $camera) {
            ScanCamera(complete: { images in camera = false; add(images) }, cancel: { camera = false })
        }

        .sheet(item: $filterPage) { page in
            FilterPickerView(page: page) { filterID in
                editPage(page.id) { $0.filter = filterID }
            }
            .environmentObject(store)
        }
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        .alert("카메라를 열 수 없습니다", isPresented: $cameraUnavailable) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("카메라를 사용할 수 없습니다. 대신 사진을 가져와 주세요.")
        }
        .alert("문서 이름 변경", isPresented: $rename) {
            TextField("문서 제목", text: $title)
            Button("저장") {
                if var d = doc { d.title = title; store.change(d) }
            }
            Button("취소", role: .cancel) {}
        }
        .onChange(of: selection) { _, items in
            Task {
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { images.append(image) }
                }
                add(images); selection = []
            }
        }
    }
    private func add(_ images: [UIImage]) {
        guard var d = doc else { return }
        store.append(images, to: &d); store.change(d)
    }
    private func editPage(_ id: UUID, action: (inout ScanPage) -> Void) {
        guard var d = doc, let i = d.pages.firstIndex(where: { $0.id == id }) else { return }
        action(&d.pages[i]); store.change(d)
    }
    private func move(_ index: Int, _ delta: Int) {
        guard var d = doc, d.pages.indices.contains(index + delta) else { return }
        d.pages.swapAt(index, index + delta); store.change(d)
    }
    private func delete(_ id: UUID) {
        guard var d = doc else { return }
        d.pages.removeAll { $0.id == id }; store.change(d)
    }
}
