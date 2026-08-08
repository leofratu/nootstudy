import Foundation
import PDFKit
import SwiftData
import ZIPFoundation

nonisolated struct AcademicRecordImporter {
    enum ImportError: Error, LocalizedError, Sendable {
        case noSupportedFiles
        case unreadableWorkbook
        case missingWorkbookSheet(String)
        case malformedWorkbook(String)

        var errorDescription: String? {
            switch self {
            case .noSupportedFiles: return "The selected folder contains no supported school-record files."
            case .unreadableWorkbook: return "The ManageBac workbook could not be read."
            case .missingWorkbookSheet(let name): return "The workbook is missing the \(name) sheet."
            case .malformedWorkbook(let detail): return "The workbook is malformed: \(detail)"
            }
        }
    }

    private static let subjectAliases: [(pattern: String, name: String, level: String)] = [
        ("russian a", "Russian A Literature", "SL"),
        ("english b", "English B", "HL"),
        ("business management", "Business Management", "HL"),
        ("business hl", "Business Management", "HL"),
        ("economics", "Economics", "HL"),
        ("biology", "Biology", "SL"),
        ("mathematics", "Mathematics AA", "SL"),
        ("math aa", "Mathematics AA", "SL"),
        ("theory of knowledge", "Theory of Knowledge", "SL"),
        ("tok", "Theory of Knowledge", "SL")
    ]

    static func preview(folder: URL) throws -> AcademicImportPreview {
        let files = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        )
        let workbook = files.first { $0.pathExtension.lowercased() == "xlsx" }
        let reports = files.filter { $0.pathExtension.lowercased() == "pdf" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let markdown = files.first { $0.pathExtension.lowercased() == "md" }
        guard workbook != nil || !reports.isEmpty || markdown != nil else {
            throw ImportError.noSupportedFiles
        }

        var warnings: [String] = []
        var assessments: [AcademicAssessmentDraft] = []
        var curriculumUnits: [AcademicCurriculumUnitDraft] = []
        if let workbook {
            do {
                let parsed = try parseWorkbook(workbook)
                assessments = parsed.assessments
                curriculumUnits = parsed.curriculumUnits
                warnings.append(contentsOf: parsed.warnings)
            } catch {
                warnings.append("Workbook: \(error.localizedDescription)")
            }
        }

        let reportSnapshots = reports.flatMap { file in
            do { return try parseReport(file) }
            catch {
                warnings.append("\(file.lastPathComponent): \(error.localizedDescription)")
                return []
            }
        }

        var sourceFiles = files.filter { $0.pathExtension.lowercased() == "xlsx" || $0.pathExtension.lowercased() == "pdf" || $0.pathExtension.lowercased() == "md" }
            .map(\.lastPathComponent)
            .sorted()
        if sourceFiles.isEmpty { sourceFiles = [folder.lastPathComponent] }

        return AcademicImportPreview(
            sourceFolderName: folder.lastPathComponent,
            sourceFingerprint: fingerprint(for: files),
            assessments: assessments,
            reportSnapshots: reportSnapshots,
            curriculumUnits: curriculumUnits,
            warnings: warnings,
            sourceFiles: sourceFiles
        )
    }

    @MainActor
    @discardableResult
    static func commit(_ preview: AcademicImportPreview, context: ModelContext) throws -> AcademicImport {
        let existing = try context.fetch(FetchDescriptor<AcademicImport>())
        if let match = existing.first(where: { $0.sourceFingerprint == preview.sourceFingerprint }) {
            return match
        }

        let importRecord = AcademicImport(
            sourceFolderName: preview.sourceFolderName,
            sourceFingerprint: preview.sourceFingerprint,
            assessmentCount: preview.assessments.count,
            curriculumUnitCount: preview.curriculumUnits.count,
            reportCount: preview.reportSnapshots.count,
            warningCount: preview.warnings.count
        )
        context.insert(importRecord)

        var subjects = try context.fetch(FetchDescriptor<Subject>())
        for name in Set(preview.assessments.map(\.subjectName) + preview.reportSnapshots.map(\.subjectName)) {
            // TOK remains valid diploma evidence for forecasting, but it is no
            // longer an enrolled study subject in this personal curriculum.
            guard name.caseInsensitiveCompare("Theory of Knowledge") != .orderedSame else { continue }
            let level = preview.assessments.first(where: { $0.subjectName == name })?.courseLevel
                ?? preview.reportSnapshots.first(where: { $0.subjectName == name })?.courseLevel
                ?? "SL"
            if subjects.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) == nil {
                let subject = Subject(name: name, level: level, accentColorHex: accentColor(for: name))
                context.insert(subject)
                subjects.append(subject)
            }
        }

        for draft in preview.assessments {
            let assessment = AcademicAssessment(
                importID: importRecord.id,
                sourceKey: draft.sourceKey,
                sourceFileName: draft.sourceFileName,
                sourceURLString: draft.sourceURLString,
                subjectName: draft.subjectName,
                courseLevel: draft.courseLevel,
                sourceClassLabel: draft.sourceClassLabel,
                assessmentDate: draft.assessmentDate,
                title: draft.title,
                assessmentType: draft.assessmentType,
                category: draft.category,
                status: draft.status,
                achievedPoints: draft.achievedPoints,
                possiblePoints: draft.possiblePoints,
                percentage: draft.percentage,
                ibScore: draft.ibScore,
                details: draft.details
            )
            context.insert(assessment)
        }

        for draft in preview.reportSnapshots {
            context.insert(AcademicReportSnapshot(
                importID: importRecord.id,
                sourceFileName: draft.sourceFileName,
                reportDate: draft.reportDate,
                subjectName: draft.subjectName,
                courseLevel: draft.courseLevel,
                gradeRaw: draft.gradeRaw,
                predictedGradeRaw: draft.predictedGradeRaw,
                effort: draft.effort,
                teacherComment: draft.teacherComment
            ))
        }

        try context.save()
        return importRecord
    }

    // MARK: - Workbook

    private struct WorkbookResult {
        let assessments: [AcademicAssessmentDraft]
        let curriculumUnits: [AcademicCurriculumUnitDraft]
        let warnings: [String]
    }

    private static func parseWorkbook(_ url: URL) throws -> WorkbookResult {
        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read) }
        catch { throw ImportError.unreadableWorkbook }

        let workbookXML = try archiveData(archive, path: "xl/workbook.xml")
        let relationshipXML = try archiveData(archive, path: "xl/_rels/workbook.xml.rels")
        let sharedStrings = (try? archiveData(archive, path: "xl/sharedStrings.xml")) ?? Data()
        let sheets = try WorkbookSheetScanner.parse(workbookXML)
        let relationships = try WorkbookRelationshipScanner.parse(relationshipXML)
        let strings = SharedStringScanner.parse(sharedStrings)

        guard let assessmentsSheet = sheets.first(where: { $0.name == "All Assessments" }) else {
            throw ImportError.missingWorkbookSheet("All Assessments")
        }
        guard let unitsSheet = sheets.first(where: { $0.name == "Curriculum Units" }) else {
            throw ImportError.missingWorkbookSheet("Curriculum Units")
        }

        let assessmentsPath = resolveSheetPath(assessmentsSheet.relationshipID, relationships)
        let unitsPath = resolveSheetPath(unitsSheet.relationshipID, relationships)
        guard let assessmentsPath, let unitsPath else {
            throw ImportError.malformedWorkbook("worksheet relationships are incomplete")
        }

        let assessmentRows = WorksheetScanner.parse(try archiveData(archive, path: assessmentsPath), sharedStrings: strings)
        let unitRows = WorksheetScanner.parse(try archiveData(archive, path: unitsPath), sharedStrings: strings)
        let (assessments, assessmentWarnings) = parseAssessmentRows(assessmentRows, fileName: url.lastPathComponent)
        let (units, unitWarnings) = parseUnitRows(unitRows)
        return WorkbookResult(assessments: assessments, curriculumUnits: units, warnings: assessmentWarnings + unitWarnings)
    }

    private static func parseAssessmentRows(_ rows: [[Int: String]], fileName: String) -> ([AcademicAssessmentDraft], [String]) {
        guard let header = rows.first else { return ([], ["All Assessments is empty"]) }
        let columns = columnIndex(header)
        let required = ["Date", "Class", "Task / Assessment", "Status"]
        let missing = required.filter { columns[$0] == nil }
        guard missing.isEmpty else { return ([], ["All Assessments is missing: \(missing.joined(separator: ", "))"]) }

        var warnings: [String] = []
        var drafts: [AcademicAssessmentDraft] = []
        for row in rows.dropFirst() where row.values.contains(where: { !$0.isEmpty }) {
            let classLabel = value(row, columns["Class"])
            let normalized = normalizeSubject(classLabel)
            guard let normalized else {
                warnings.append("Unrecognized class: \(classLabel)")
                continue
            }
            let title = value(row, columns["Task / Assessment"])
            let date = parseDate(value(row, columns["Date"]))
            let achieved = parseDouble(value(row, columns["Points Earned"]))
            let possible = parseDouble(value(row, columns["Points Possible"]))
            let percent = parseDouble(value(row, columns["Percent"]))
            let grade = Int(value(row, columns["Grade"]))
            let url = value(row, columns["Source URL"])
            let key = sourceKey(classLabel: classLabel, title: title, date: date, sourceURL: url)
            drafts.append(AcademicAssessmentDraft(
                sourceKey: key,
                sourceFileName: fileName,
                sourceURLString: url.isEmpty ? nil : url,
                subjectName: normalized.name,
                courseLevel: normalized.level,
                sourceClassLabel: classLabel,
                assessmentDate: date,
                title: title,
                assessmentType: value(row, columns["Assessment Type"]),
                category: value(row, columns["Category"]),
                status: value(row, columns["Status"]),
                achievedPoints: achieved,
                possiblePoints: possible,
                percentage: percent,
                ibScore: grade,
                details: value(row, columns["Details"])
            ))
        }
        return (drafts, warnings)
    }

    private static func parseUnitRows(_ rows: [[Int: String]]) -> ([AcademicCurriculumUnitDraft], [String]) {
        guard let header = rows.first else { return ([], ["Curriculum Units is empty"]) }
        let columns = columnIndex(header)
        guard columns["Class"] != nil, columns["Unit / Topic"] != nil else {
            return ([], ["Curriculum Units is missing Class or Unit / Topic"])
        }
        var warnings: [String] = []
        let units = rows.dropFirst().compactMap { row -> AcademicCurriculumUnitDraft? in
            let sourceClass = value(row, columns["Class"])
            guard let _ = normalizeSubject(sourceClass) else {
                warnings.append("Unrecognized curriculum class: \(sourceClass)")
                return nil
            }
            return AcademicCurriculumUnitDraft(
                sourceClassLabel: sourceClass,
                unitName: value(row, columns["Unit / Topic"]),
                scheduledStart: value(row, columns["Scheduled Start"]),
                durationWeeks: parseDouble(value(row, columns["Duration (weeks)"])),
                status: value(row, columns["ManageBac Status"]),
                lessonsListed: Int(value(row, columns["Lessons Listed"])),
                tasksLinked: Int(value(row, columns["Tasks Linked"])),
                sourceURLString: {
                    let sourceURL = value(row, columns["Source URL"])
                    return sourceURL.isEmpty ? nil : sourceURL
                }()
            )
        }
        return (Array(units), warnings)
    }

    // MARK: - Reports

    private static func parseReport(_ url: URL) throws -> [AcademicReportDraft] {
        guard let document = PDFDocument(url: url) else { throw ImportError.malformedWorkbook("PDF could not be opened") }
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        let reportDate = firstDate(in: text)
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var snapshots: [AcademicReportDraft] = []
        for (index, line) in lines.enumerated() {
            guard let subject = normalizeSubject(line) else { continue }
            let context = lines[index..<min(index + 12, lines.count)].joined(separator: " ")
            let grade = firstMatch(pattern: #"\b([1-7]|[A-E])\b"#, in: context) ?? ""
            let effort = firstMatch(pattern: #"(Highly Effective|Mostly Effective|Effective|Developing|Good|Excellent)"#, in: context) ?? ""
            snapshots.append(AcademicReportDraft(
                sourceFileName: url.lastPathComponent,
                reportDate: reportDate,
                subjectName: subject.name,
                courseLevel: subject.level,
                gradeRaw: grade,
                predictedGradeRaw: "",
                effort: effort,
                teacherComment: ""
            ))
        }
        var seen = Set<String>()
        return snapshots.filter { snapshot in
            seen.insert("\(snapshot.sourceFileName)|\(snapshot.subjectName)").inserted
        }
    }

    // MARK: - Helpers

    private static func archiveData(_ archive: Archive, path: String) throws -> Data {
        guard let entry = archive[path] else { throw ImportError.malformedWorkbook("missing \(path)") }
        var result = Data()
        _ = try archive.extract(entry) { result.append($0) }
        return result
    }

    private static func resolveSheetPath(_ relationshipID: String, _ relationships: [String: String]) -> String? {
        guard let target = relationships[relationshipID] else { return nil }
        let clean = target.hasPrefix("/") ? String(target.dropFirst()) : target
        if clean.hasPrefix("xl/") { return clean }
        return "xl/\(clean.replacingOccurrences(of: "../", with: ""))"
    }

    private static func columnIndex(_ row: [Int: String]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: row.compactMap { index, value in
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? nil : (key, index)
        })
    }

    private static func value(_ row: [Int: String], _ column: Int?) -> String {
        guard let column else { return "" }
        return row[column]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func parseDouble(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: "%", with: ""))
    }

    private static func parseDate(_ value: String) -> Date? {
        guard let serial = Double(value), serial > 10_000 else {
            let formats = ["yyyy-MM-dd", "dd/MM/yyyy", "MMM d, yyyy"]
            for format in formats {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = format
                if let date = formatter.date(from: value) { return date }
            }
            return nil
        }
        return Date(timeIntervalSinceReferenceDate: (serial - 25569) * 86_400)
    }

    private static func firstDate(in text: String) -> Date? {
        let value = firstMatch(pattern: #"(?:Prepared:|Prepared)\s*([A-Za-z]+\s+\d{1,2},\s+\d{4})"#, in: text) ?? ""
        return parseDate(value)
    }

    private static func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }

    private static func normalizeSubject(_ raw: String) -> (name: String, level: String)? {
        let normalized = raw.lowercased().replacingOccurrences(of: ":", with: " ")
        return subjectAliases.first(where: { normalized.contains($0.pattern) }).map { ($0.name, $0.level) }
    }

    private static func sourceKey(classLabel: String, title: String, date: Date?, sourceURL: String) -> String {
        [classLabel.lowercased(), title.lowercased(), date?.timeIntervalSince1970.description ?? "", sourceURL.lowercased()]
            .joined(separator: "|")
    }

    private static func fingerprint(for files: [URL]) -> String {
        files.sorted { $0.path < $1.path }.map { file in
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return "\(file.lastPathComponent)|\(values?.fileSize ?? 0)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }.joined(separator: "\n")
    }

    private static func accentColor(for subject: String) -> String {
        switch subject {
        case "English B": return "8B5CF6"
        case "Russian A Literature": return "EC4899"
        case "Biology": return "10B981"
        case "Mathematics AA": return "3B82F6"
        case "Economics": return "F59E0B"
        case "Business Management": return "EF4444"
        case "Theory of Knowledge": return "14B8A6"
        default: return "2868E8"
        }
    }
}

nonisolated private final class WorkbookSheetScanner: NSObject, XMLParserDelegate {
    struct Sheet { let name: String; let relationshipID: String }
    private var sheets: [Sheet] = []

    static func parse(_ data: Data) throws -> [Sheet] {
        let scanner = WorkbookSheetScanner()
        let parser = XMLParser(data: data)
        parser.delegate = scanner
        guard parser.parse() else { throw AcademicRecordImporter.ImportError.malformedWorkbook("sheet list") }
        return scanner.sheets
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        guard localName == "sheet", let name = attributeDict["name"], let relationshipID = attributeDict["r:id"] ?? attributeDict["id"] else { return }
        sheets.append(Sheet(name: name, relationshipID: relationshipID))
    }
}

nonisolated private final class WorkbookRelationshipScanner: NSObject, XMLParserDelegate {
    private var relationships: [String: String] = [:]

    static func parse(_ data: Data) throws -> [String: String] {
        let scanner = WorkbookRelationshipScanner()
        let parser = XMLParser(data: data)
        parser.delegate = scanner
        guard parser.parse() else { throw AcademicRecordImporter.ImportError.malformedWorkbook("relationships") }
        return scanner.relationships
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "Relationship", let id = attributeDict["Id"], let target = attributeDict["Target"] else { return }
        relationships[id] = target
    }
}

nonisolated private final class SharedStringScanner: NSObject, XMLParserDelegate {
    private var values: [String] = []
    private var current = ""
    private var insideText = false

    static func parse(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        let scanner = SharedStringScanner()
        let parser = XMLParser(data: data)
        parser.delegate = scanner
        _ = parser.parse()
        return scanner.values
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if localName == "t" { insideText = true; current = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if localName == "t" { values.append(current); insideText = false }
    }
}

nonisolated private final class WorksheetScanner: NSObject, XMLParserDelegate {
    private var rows: [[Int: String]] = []
    private var currentRow: [Int: String] = [:]
    private var currentColumn: Int?
    private var currentType = ""
    private var currentValue = ""
    private var insideValue = false
    private let sharedStrings: [String]

    private init(sharedStrings: [String]) { self.sharedStrings = sharedStrings }

    static func parse(_ data: Data, sharedStrings: [String]) -> [[Int: String]] {
        let scanner = WorksheetScanner(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = scanner
        _ = parser.parse()
        return scanner.rows
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        switch localName {
        case "row": currentRow = [:]
        case "c":
            currentColumn = Self.columnNumber(from: attributeDict["r"])
            currentType = attributeDict["t"] ?? ""
            currentValue = ""
        case "v", "t": insideValue = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideValue { currentValue += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        switch localName {
        case "v", "t": insideValue = false
        case "c":
            if let currentColumn {
                let value: String
                if currentType == "s", let index = Int(currentValue), sharedStrings.indices.contains(index) {
                    value = sharedStrings[index]
                } else {
                    value = currentValue
                }
                currentRow[currentColumn] = value
            }
            currentColumn = nil
        case "row":
            if !currentRow.isEmpty { rows.append(currentRow) }
        default: break
        }
    }

    private static func columnNumber(from reference: String?) -> Int? {
        guard let reference else { return nil }
        let letters = reference.prefix { $0.isLetter }
        guard !letters.isEmpty else { return nil }
        return letters.reduce(0) { $0 * 26 + Int($1.asciiValue ?? 64) - 64 } - 1
    }
}
