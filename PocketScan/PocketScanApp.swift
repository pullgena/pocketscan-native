import SwiftUI
import UIKit
import VisionKit
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
    func image(_ page: ScanPage) -> UIImage? {
        guard let original = UIImage(contentsOfFile: folder.appendingPathComponent(page.file).path) else { return nil }
        var output = original
        if page.filter != 0, let ci = CIImage(image: original) {
            let filter: CIFilter
            switch page.filter {
            case 1:
                let f = CIFilter.colorControls()
                f.inputImage = ci; f.contrast = 1.28; f.saturation = 1.08; f.brightness = 0.03
                filter = f
            case 2:
                let f = CIFilter.colorControls()
                f.inputImage = ci; f.saturation = 0
                filter = f
            default:
                let f = CIFilter.photoEffectNoir()
                f.inputImage = ci; filter = f
            }
            if let result = filter.outputImage, let cg = CIContext().createCGImage(result, from: result.extent) { output = UIImage(cgImage: cg) }
        }
        if page.rotation != 0 {
            let angle = CGFloat(page.rotation) * .pi / 180
            let canvas = CGRect(origin: .zero, size: output.size).applying(CGAffineTransform(rotationAngle: angle)).standardized.size
            let format = UIGraphicsImageRendererFormat(); format.scale = output.scale
            output = UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
                ctx.cgContext.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                ctx.cgContext.rotate(by: angle)
                output.draw(in: CGRect(x: -output.size.width / 2, y: -output.size.height / 2, width: output.size.width, height: output.size.height))
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

struct ScanCamera: UIViewControllerRepresentable {
    var complete: ([UIImage]) -> Void
    var cancel: () -> Void
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let c = VNDocumentCameraViewController(); c.delegate = context.coordinator; return c
    }
    func updateUIViewController(_ c: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: ScanCamera
        init(_ parent: ScanCamera) { self.parent = parent }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            parent.complete((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.cancel() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.cancel() }
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

struct HomeView: View {
    @EnvironmentObject var store: ScanStore
    @State private var camera = false
    @State private var selection: [PhotosPickerItem] = []
    @State private var scanned: UUID?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("포켓스캔", systemImage: "doc.viewfinder").font(.largeTitle.bold()).foregroundStyle(.teal)
                        Text("서류부터 문제집까지, 간편하게 스캔하세요.").foregroundStyle(.secondary)
                    }.padding(.top)
                    Button { camera = true } label: {
                        Label("새 문서 스캔", systemImage: "camera.viewfinder")
                            .font(.title3.bold()).frame(maxWidth: .infinity).padding(20)
                    }.buttonStyle(.borderedProminent).tint(.teal)
                    PhotosPicker(selection: $selection, maxSelectionCount: 30, matching: .images) {
                        Label("사진에서 불러오기", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity).padding(12)
                    }.buttonStyle(.bordered)
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

struct EditorView: View {
    @EnvironmentObject var store: ScanStore
    @Environment(\.dismiss) var dismiss
    let docID: UUID
    @State private var camera = false
    @State private var selection: [PhotosPickerItem] = []
    @State private var share: SharePDF?
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
                                    Menu {
                                        ForEach(0..<4, id: \.self) { f in
                                            Button(["원본", "선명하게", "회색", "흑백"][f]) {
                                                editPage(page.id) { $0.filter = f }
                                            }
                                        }
                                    } label: { Label("필터", systemImage: "slider.horizontal.3") }
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
                Button { camera = true } label: { Image(systemName: "camera") }
                PhotosPicker(selection: $selection, maxSelectionCount: 30, matching: .images) { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $camera) {
            ScanCamera(complete: { images in camera = false; add(images) }, cancel: { camera = false })
        }
        .sheet(item: $share) { ShareSheet(url: $0.url) }
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
