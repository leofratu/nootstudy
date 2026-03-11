import SwiftUI
import QuickLook

// MARK: - Material Category
struct MaterialCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    let subject: String  // maps to IB subject
    let subfolder: String  // relative path inside Materials
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
        default: return IBColors.mutedGray
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
        ZStack {
            IBColors.navy.ignoresSafeArea()
            IBColors.meshGlow.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: IBSpacing.lg) {
                    // Search
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundColor(IBColors.mutedGray)
                        TextField("Search materials...", text: $searchText)
                            .font(IBTypography.body)
                            .foregroundColor(IBColors.softWhite)
                    }
                    .padding(12)
                    .glassCard(cornerRadius: IBRadius.sm)

                    // Stats
                    let allFiles = getAllFiles()
                    HStack(spacing: IBSpacing.md) {
                        StatCard(value: "\(categories.count)", label: "Collections", color: IBColors.electricBlue, icon: "folder.fill")
                        StatCard(value: "\(allFiles.count)", label: "Files", color: IBColors.success, icon: "doc.fill")
                        let totalMB = allFiles.reduce(0) { $0 + $1.size } / 1_000_000
                        StatCard(value: "\(totalMB) MB", label: "Total", color: IBColors.warning, icon: "internaldrive")
                    }
                    .padding(.vertical, 4)

                    // Categories
                    ForEach(filteredCategories) { cat in
                        NavigationLink {
                            MaterialFolderView(category: cat, previewURL: $previewURL)
                        } label: {
                            categoryCard(cat)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, IBSpacing.md)
                .padding(.bottom, 100)
            }
        }
        .navigationTitle("Materials Library")
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($previewURL)
    }

    private var filteredCategories: [MaterialCategory] {
        if searchText.isEmpty { return categories }
        return categories.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.subject.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func categoryCard(_ cat: MaterialCategory) -> some View {
        GlassCard(cornerRadius: IBRadius.md, padding: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(cat.color.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: cat.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(cat.color)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(cat.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(IBColors.softWhite)
                    Text(cat.description)
                        .font(.system(size: 11))
                        .foregroundColor(IBColors.mutedGray)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(cat.subject)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(cat.color.opacity(0.8))
                        let count = getFileCount(for: cat)
                        Text("• \(count) files")
                            .font(.system(size: 10))
                            .foregroundColor(IBColors.tertiaryText)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(IBColors.tertiaryText)
            }
        }
    }

    private func getFileCount(for cat: MaterialCategory) -> Int {
        let base = Bundle.main.resourceURL?.deletingLastPathComponent()
            .appendingPathComponent("IBVault/Materials/\(cat.subfolder)") ?? URL(fileURLWithPath: "")
        let materialsBase = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/IBVault_Materials/\(cat.subfolder)")
        // Try app bundle first, then documents
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

// MARK: - Material Folder View
struct MaterialFolderView: View {
    let category: MaterialCategory
    @Binding var previewURL: URL?
    @State private var files: [MaterialFile] = []
    @State private var subfolders: [(name: String, url: URL)] = []
    @State private var currentPath: URL?
    @State private var searchText = ""

    var body: some View {
        ZStack {
            IBColors.navy.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: IBSpacing.md) {
                    // Header info
                    GlassCard(cornerRadius: IBRadius.md, padding: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: category.icon).foregroundColor(category.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.subject)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(category.color)
                                Text("\(files.count) files\(subfolders.isEmpty ? "" : " • \(subfolders.count) folders")")
                                    .font(.system(size: 11)).foregroundColor(IBColors.mutedGray)
                            }
                            Spacer()
                        }
                    }

                    // Search
                    if files.count + subfolders.count > 5 {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundColor(IBColors.mutedGray).font(.system(size: 13))
                            TextField("Filter...", text: $searchText)
                                .font(.system(size: 13)).foregroundColor(IBColors.softWhite)
                        }
                        .padding(10)
                        .glassCard(cornerRadius: IBRadius.sm)
                    }

                    // Subfolders
                    if !filteredSubfolders.isEmpty {
                        ForEach(filteredSubfolders, id: \.name) { folder in
                            NavigationLink {
                                SubfolderView(name: folder.name, url: folder.url, color: category.color, previewURL: $previewURL)
                            } label: {
                                GlassCard(cornerRadius: IBRadius.sm, padding: 10) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "folder.fill")
                                            .foregroundColor(category.color.opacity(0.7))
                                            .font(.system(size: 15))
                                        Text(folder.name)
                                            .font(IBTypography.captionBold).foregroundColor(IBColors.softWhite)
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(IBColors.tertiaryText)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Files
                    if !filteredFiles.isEmpty {
                        ForEach(filteredFiles) { file in
                            fileRow(file)
                        }
                    }
                }
                .padding(.horizontal, IBSpacing.md)
                .padding(.bottom, 100)
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
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
            GlassCard(cornerRadius: IBRadius.sm, padding: 10) {
                HStack(spacing: 10) {
                    Image(systemName: file.icon)
                        .foregroundColor(file.iconColor)
                        .font(.system(size: 15))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name.replacingOccurrences(of: ".\(file.ext)", with: ""))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(IBColors.softWhite)
                            .lineLimit(2)
                        Text("\(file.ext.uppercased()) • \(file.sizeFormatted)")
                            .font(.system(size: 10)).foregroundColor(IBColors.mutedGray)
                    }
                    Spacer()
                    Image(systemName: "eye.fill").font(.system(size: 12)).foregroundColor(IBColors.tertiaryText)
                }
            }
        }
        .buttonStyle(.plain)
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
        ZStack {
            IBColors.navy.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: IBSpacing.md) {
                    ForEach(subfolders, id: \.name) { folder in
                        NavigationLink {
                            SubfolderView(name: folder.name, url: folder.url, color: color, previewURL: $previewURL)
                        } label: {
                            GlassCard(cornerRadius: IBRadius.sm, padding: 10) {
                                HStack(spacing: 10) {
                                    Image(systemName: "folder.fill").foregroundColor(color.opacity(0.7))
                                    Text(folder.name).font(IBTypography.captionBold).foregroundColor(IBColors.softWhite)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(IBColors.tertiaryText)
                                }
                            }
                        }.buttonStyle(.plain)
                    }

                    ForEach(files) { file in
                        Button { previewURL = file.url } label: {
                            GlassCard(cornerRadius: IBRadius.sm, padding: 10) {
                                HStack(spacing: 10) {
                                    Image(systemName: file.icon).foregroundColor(file.iconColor)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.name.replacingOccurrences(of: ".\(file.ext)", with: ""))
                                            .font(.system(size: 13, weight: .medium)).foregroundColor(IBColors.softWhite).lineLimit(2)
                                        Text("\(file.ext.uppercased()) • \(file.sizeFormatted)")
                                            .font(.system(size: 10)).foregroundColor(IBColors.mutedGray)
                                    }
                                    Spacer()
                                    Image(systemName: "eye.fill").font(.system(size: 12)).foregroundColor(IBColors.tertiaryText)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, IBSpacing.md)
                .padding(.bottom, 100)
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let (f, s) = loadDirectory(url)
            files = f; subfolders = s
        }
    }
}

// MARK: - Helpers

func getMaterialsURL(for subfolder: String) -> URL {
    // Materials are bundled in the app
    if let url = Bundle.main.url(forResource: subfolder, withExtension: nil, subdirectory: "Materials") {
        return url
    }
    // Fallback: project directory (dev mode)
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
        files.append(MaterialFile(
            name: name, url: fileURL,
            size: Int64(values.fileSize ?? 0),
            ext: fileURL.pathExtension
        ))
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
