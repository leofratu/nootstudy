import SwiftUI
import QuickLook

// MARK: - Material Category
struct MaterialCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    let subject: String
    let subfolder: String
    let description: String
}

struct MaterialFile: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    let size: Int64
    let ext: String

    var sizeFormatted: String {
        if size > 1_000_000 { return "\(size / 1_000_000) MB" }
        if size > 1_000 { return "\(size / 1_000) KB" }
        return "\(size) B"
    }

    var icon: String {
        switch ext.lowercased() {
        case "pdf": return "doc.richtext.fill"
        case "pptx", "ppt": return "rectangle.stack.fill"
        case "js": return "curlybraces"
        case "txt": return "doc.text"
        default: return "doc.fill"
        }
    }

    var iconColor: Color {
        switch ext.lowercased() {
        case "pdf": return IBColors.danger
        case "pptx", "ppt": return IBColors.streakOrange
        case "js": return IBColors.warning
        default: return .gray
        }
    }
}

struct MaterialsLibraryView: View {
    @State private var searchText = ""
    @State private var previewURL: URL?

    private let categories: [MaterialCategory] = [
        MaterialCategory(name: "Bananaomics", icon: "chart.bar.fill", color: IBColors.economicsColor,
                         subject: "Economics", subfolder: "Bananaomics 2022",
                         description: "Full IB Economics course — Micro, Macro, Global Economy"),
        MaterialCategory(name: "ibGenius BM", icon: "briefcase.fill", color: IBColors.businessColor,
                         subject: "Business Management", subfolder: "ibGenius",
                         description: "BM Toolkit, mock papers M23–M25, revision quizzes"),
        MaterialCategory(name: "IB English Guys", icon: "text.book.closed.fill", color: IBColors.englishColor,
                         subject: "English B", subfolder: "IB English Guys",
                         description: "Paper 1 & 2 guides, IO planning, HL essay resources"),
        MaterialCategory(name: "LitLearn", icon: "book.fill", color: IBColors.russianColor,
                         subject: "Russian A Literature", subfolder: "LitLearn",
                         description: "Full study guides for Language A Literature"),
        MaterialCategory(name: "Grade Boundaries", icon: "chart.line.uptrend.xyaxis", color: IBColors.electricBlue,
                         subject: "All Subjects", subfolder: "IB DOCUMENTS/Grade Boundaries",
                         description: "Official IB grade boundaries 2011–2025"),
        MaterialCategory(name: "Formula Booklets", icon: "function", color: IBColors.mathColor,
                         subject: "Math & BM & Econ", subfolder: "IB DOCUMENTS/Data and Formula Booklets",
                         description: "Official IB formula and data booklets"),
        MaterialCategory(name: "Subject Reports", icon: "doc.text.magnifyingglass", color: IBColors.success,
                         subject: "All Subjects", subfolder: "IB SUBJECT REPORTS",
                         description: "Examiner reports — understand how IB marks"),
        MaterialCategory(name: "Teacher Support", icon: "person.crop.rectangle.fill", color: IBColors.warning,
                         subject: "All Subjects", subfolder: "IB TEACHER SUPPORT MATERIAL",
                         description: "TSMs with assessed student work samples"),
        MaterialCategory(name: "IB Official Docs", icon: "building.columns.fill", color: IBColors.electricBlueMuted,
                         subject: "General", subfolder: "IB DOCUMENTS",
                         description: "Exam procedures, calculators policy, academic honesty"),
        MaterialCategory(name: "Question Bank", icon: "questionmark.circle.fill", color: IBColors.biologyColor,
                         subject: "Multiple", subfolder: "revision-town-2024",
                         description: "Past paper question data bank")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Search + summary
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search materials…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                // Library stats
                librarySummary
                    .padding(.horizontal, 24)

                // Collection grid
                let columns = [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)]
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(filteredCategories) { cat in
                        NavigationLink {
                            MaterialFolderView(category: cat, previewURL: $previewURL)
                        } label: {
                            CollectionCard(category: cat, fileCount: getFileCount(for: cat))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .background(.background)
        .navigationTitle("Materials Library")
        .quickLookPreview($previewURL)
    }

    private var librarySummary: some View {
        HStack(spacing: 0) {
            let allFiles = getAllFiles()
            let totalMB = allFiles.reduce(0) { $0 + $1.size } / 1_000_000
            StatCard(value: "\(categories.count)", label: "Collections", color: IBColors.electricBlue, icon: "folder.fill")
            Divider().frame(height: 40)
            StatCard(value: "\(allFiles.count)", label: "Files", color: .orange, icon: "doc.fill")
            Divider().frame(height: 40)
            StatCard(value: "\(totalMB) MB", label: "Total Size", color: .green, icon: "externaldrive.fill")
        }
        .padding(.vertical, 12)
        .glassCard()
    }

    private var filteredCategories: [MaterialCategory] {
        if searchText.isEmpty { return categories }
        return categories.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.subject.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func getFileCount(for cat: MaterialCategory) -> Int {
        return countFiles(in: getMaterialsURL(for: cat.subfolder))
    }

    private func getAllFiles() -> [MaterialFile] {
        categories.flatMap { cat in
            listFiles(in: getMaterialsURL(for: cat.subfolder))
        }
    }

    private func countFiles(in url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else { return 0 }
        var count = 0
        for case let fileURL as URL in enumerator {
            if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { count += 1 }
        }
        return count
    }
}

// MARK: - Collection Card
struct CollectionCard: View {
    let category: MaterialCategory
    let fileCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(category.color.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: category.icon)
                        .foregroundStyle(category.color)
                        .font(.system(size: 16, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.callout.weight(.semibold))
                    Text(category.subject)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(fileCount)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(category.color.opacity(0.1)))
                    .foregroundStyle(category.color)
            }

            Text(category.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .glassCard()
        .contentShape(Rectangle())
    }
}

// MARK: - Material Folder View
struct MaterialFolderView: View {
    let category: MaterialCategory
    @Binding var previewURL: URL?
    @State private var files: [MaterialFile] = []
    @State private var subfolders: [(name: String, url: URL)] = []
    @State private var currentPath: URL?
    @State private var searchText = ""

    var body: some View {
        List {
            if files.count + subfolders.count > 5 {
                Section {
                    TextField("Filter…", text: $searchText)
                }
            }

            if !filteredSubfolders.isEmpty {
                Section("Folders") {
                    ForEach(filteredSubfolders, id: \.name) { folder in
                        NavigationLink {
                            SubfolderView(name: folder.name, url: folder.url, color: category.color, previewURL: $previewURL)
                        } label: {
                            Label(folder.name, systemImage: "folder.fill")
                                .foregroundStyle(category.color)
                        }
                    }
                }
            }

            if !filteredFiles.isEmpty {
                Section("Files (\(filteredFiles.count))") {
                    ForEach(filteredFiles) { file in
                        fileRow(file)
                    }
                }
            }
        }
        .navigationTitle(category.name)
        .onAppear { loadContents() }
    }

    private var filteredFiles: [MaterialFile] {
        if searchText.isEmpty { return files }
        return files.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredSubfolders: [(name: String, url: URL)] {
        if searchText.isEmpty { return subfolders }
        return subfolders.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func fileRow(_ file: MaterialFile) -> some View {
        Button {
            previewURL = file.url
        } label: {
            HStack(spacing: 10) {
                Image(systemName: file.icon)
                    .foregroundStyle(file.iconColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name.replacingOccurrences(of: ".\(file.ext)", with: ""))
                        .lineLimit(1)
                    Text("\(file.ext.uppercased()) • \(file.sizeFormatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private func loadContents() {
        let url = getMaterialsURL(for: category.subfolder)
        currentPath = url
        let (f, s) = loadDirectory(url)
        files = f; subfolders = s
    }
}

// MARK: - Subfolder View
struct SubfolderView: View {
    let name: String
    let url: URL
    let color: Color
    @Binding var previewURL: URL?
    @State private var files: [MaterialFile] = []
    @State private var subfolders: [(name: String, url: URL)] = []

    var body: some View {
        List {
            if !subfolders.isEmpty {
                Section("Folders") {
                    ForEach(subfolders, id: \.name) { folder in
                        NavigationLink {
                            SubfolderView(name: folder.name, url: folder.url, color: color, previewURL: $previewURL)
                        } label: {
                            Label(folder.name, systemImage: "folder.fill")
                                .foregroundStyle(color)
                        }
                    }
                }
            }

            if !files.isEmpty {
                Section("Files (\(files.count))") {
                    ForEach(files) { file in
                        Button {
                            previewURL = file.url
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: file.icon)
                                    .foregroundStyle(file.iconColor)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name.replacingOccurrences(of: ".\(file.ext)", with: ""))
                                        .lineLimit(1)
                                    Text("\(file.ext.uppercased()) • \(file.sizeFormatted)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(name)
        .onAppear {
            let (f, s) = loadDirectory(url)
            files = f; subfolders = s
        }
    }
}

// MARK: - Helpers

func getMaterialsURL(for subfolder: String) -> URL {
    if let url = Bundle.main.url(forResource: subfolder, withExtension: nil, subdirectory: "Materials") {
        return url
    }
    return URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Materials/\(subfolder)")
}

func listFiles(in url: URL) -> [MaterialFile] {
    guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return [] }
    var files: [MaterialFile] = []
    for case let fileURL as URL in enumerator {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true else { continue }
        let name = fileURL.lastPathComponent
        guard !name.hasPrefix(".") else { continue }
        files.append(MaterialFile(name: name, url: fileURL, size: Int64(values.fileSize ?? 0), ext: fileURL.pathExtension))
    }
    return files.sorted { $0.name < $1.name }
}

func loadDirectory(_ url: URL) -> (files: [MaterialFile], subfolders: [(name: String, url: URL)]) {
    guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) else {
        return ([], [])
    }
    var files: [MaterialFile] = []
    var folders: [(name: String, url: URL)] = []
    for item in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let name = item.lastPathComponent
        guard !name.hasPrefix(".") else { continue }
        if let values = try? item.resourceValues(forKeys: [.isDirectoryKey]),
           values.isDirectory == true {
            folders.append((name: name, url: item))
        } else {
            files.append(MaterialFile(
                name: name, url: item,
                size: Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0),
                ext: item.pathExtension
            ))
        }
    }
    return (files, folders)
}
