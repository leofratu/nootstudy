import Foundation

/// Canonical authority for visual content that ARIA can mount inside chat.
/// Providers emit data only; the app validates it and owns all rendering,
/// animation, controls, gestures, and accessibility behavior.
nonisolated enum ARIAContentContract: Sendable {
    static let toolName = "render_interactive_canvas"
    static let primaryFenceLanguage = "aria-canvas"
    static let acceptedFenceLanguages = Set(["aria-canvas", "canvas", "diagram", "diagram-json", "json"])
    static let supportedTypes = Set(["coordinate", "flow", "simulation", "canvas"])
    static let supportedElementKinds = Set(["circle", "rect", "rectangle", "line", "arrow", "vector", "text", "label", "polyline"])
    static let supportedAnimations = Set(["orbit", "circle", "sine", "wave", "linear", "drift", "bounce", "vibrate"])

    static let capabilitySummary = """
    - You have the \(toolName) content tool. Use it whenever a graph, diagram, model, or adjustable simulation makes the explanation materially clearer, and always use it when the learner explicitly asks for an interactive visual.
    - Invoke it by appending exactly one fenced \(primaryFenceLanguage) JSON object after the explanation. Never emit HTML, JavaScript, SVG, Mermaid, executable code, or a capability disclaimer.
    """

    static var systemInstruction: String {
        let fence = String(repeating: "`", count: 3)
        return """
        INTERACTIVE CANVAS TOOL — \(toolName)

        The native macOS chat can mount a validated interactive canvas directly inside your answer. Choose this tool when a visual relationship, graph, process, particle model, atom model, vector, or adjustable parameter would teach better than prose alone. If the learner explicitly requests a canvas, graph, diagram, animation, atom, particle system, or simulation, the tool call is required.

        Output contract:
        1. Give a concise explanation in normal Markdown.
        2. Append one JSON object in a fenced block labelled \(primaryFenceLanguage).
        3. Use normalized coordinates from 0 to 1. Use only the documented fields and supported kinds.
        4. Do not describe the JSON as data for another viewer. The app renders it immediately.

        Coordinate graph:
        \(fence)\(primaryFenceLanguage)
        {"type":"coordinate","title":"Quadratic family","xLabel":"x","yLabel":"y","series":[{"label":"y = x^2","color":"#2563EB","points":[[-2,4],[-1,1],[0,0],[1,1],[2,4]]}]}
        \(fence)

        Flow diagram:
        \(fence)\(primaryFenceLanguage)
        {"type":"flow","title":"Causal chain","nodes":[{"id":"a","label":"Cause","x":0.2,"y":0.5},{"id":"b","label":"Mechanism","x":0.5,"y":0.5},{"id":"c","label":"Outcome","x":0.8,"y":0.5}],"edges":[{"from":"a","to":"b","label":"drives"},{"from":"b","to":"c","label":"produces"}]}
        \(fence)

        Interactive canvas:
        \(fence)\(primaryFenceLanguage)
        {"type":"canvas","title":"Adjustable pendulum","canvas":{"controls":[{"id":"amplitude","label":"Amplitude","min":0.02,"max":0.3,"value":0.12,"unit":" rad","kind":"slider"},{"id":"speed","label":"Speed","min":0.2,"max":3,"value":1,"unit":"x","kind":"slider"},{"id":"labels","label":"Show labels","min":0,"max":1,"value":1,"kind":"toggle"}],"elements":[{"id":"pivot","kind":"circle","x":0.5,"y":0.18,"radius":0.018,"color":"#111827"},{"id":"arm","kind":"line","x":0.5,"y":0.18,"x2":0.5,"y2":0.62,"color":"#64748B"},{"id":"bob","kind":"circle","x":0.5,"y":0.62,"radius":0.045,"color":"#2563EB","label":"mass","animation":"sine","amplitudeControl":"amplitude","speedControl":"speed","visibilityControl":"labels"}]}}
        \(fence)

        Schema:
        - type coordinate: title, xLabel, yLabel, series. Each series has label, optional color, and numeric points [[x,y], ...].
        - type flow: title, nodes with unique id/label and optional normalized x/y/color, plus edges with from/to and optional label.
        - type simulation: title, simulation set to atoms or particles, and optional particleCount from 4 to 64.
        - type canvas: canvas.elements plus optional canvas.controls.
        - element kinds: circle, rect, line, arrow, vector, text, polyline. Coordinates x/y/x2/y2 and sizes are normalized. Polyline uses points [[x,y], ...].
        - animations: orbit, sine, linear, bounce, vibrate. Elements may reference speedControl, amplitudeControl, radiusControl, and visibilityControl.
        - controls: unique id, label, min, max, value, optional unit, and kind slider or toggle.
        """
    }

    static func decodeDiagram(from code: String, language: String) -> ARIADiagramSpec? {
        let normalizedLanguage = language
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard acceptedFenceLanguages.contains(normalizedLanguage),
              let diagram = try? JSONDecoder().decode(ARIADiagramSpec.self, from: Data(code.utf8)),
              validate(diagram) else {
            return nil
        }
        return diagram
    }

    static func validate(_ diagram: ARIADiagramSpec) -> Bool {
        let type = diagram.type.lowercased()
        guard supportedTypes.contains(type) else { return false }
        switch type {
        case "coordinate":
            let series = diagram.graphSeries
            return !series.isEmpty && series.count <= 12 && series.allSatisfy { item in
                !item.points.isEmpty && item.points.count <= 256 && item.points.allSatisfy(validPoint)
            }
        case "flow":
            let nodes = diagram.flowNodes
            let ids = nodes.map(\.id)
            let idSet = Set(ids)
            return !nodes.isEmpty && nodes.count <= 40 && idSet.count == ids.count &&
                nodes.allSatisfy { !$0.id.isEmpty && !$0.label.isEmpty && validOptionalCoordinate($0.x) && validOptionalCoordinate($0.y) } &&
                diagram.flowEdges.count <= 80 && diagram.flowEdges.allSatisfy { idSet.contains($0.from) && idSet.contains($0.to) }
        case "simulation":
            let mode = diagram.simulation?.lowercased() ?? ""
            return ["atoms", "particles"].contains(mode) && (4...64).contains(diagram.particleCount ?? 18)
        case "canvas":
            guard let canvas = diagram.canvas,
                  !canvas.elements.isEmpty,
                  canvas.elements.count <= 160 else { return false }
            let controls = canvas.controls ?? []
            let controlIDs = controls.map(\.id)
            let controlSet = Set(controlIDs)
            guard controls.count <= 16,
                  controlSet.count == controlIDs.count,
                  controls.allSatisfy(validControl) else { return false }
            return canvas.elements.allSatisfy { validElement($0, controlIDs: controlSet) }
        default:
            return false
        }
    }

    private static func validPoint(_ point: [Double]) -> Bool {
        point.count >= 2 && point[0].isFinite && point[1].isFinite
    }

    private static func validOptionalCoordinate(_ value: Double?) -> Bool {
        guard let value else { return true }
        return value.isFinite && (-0.1...1.1).contains(value)
    }

    private static func validControl(_ control: ARIADiagramSpec.CanvasScene.Control) -> Bool {
        !control.id.isEmpty && !control.label.isEmpty && control.min.isFinite && control.max.isFinite &&
            control.value.isFinite && control.max > control.min &&
            abs(control.min) <= 10_000 && abs(control.max) <= 10_000 &&
            (control.min...control.max).contains(control.value) &&
            (control.kind == nil || ["slider", "toggle"].contains(control.kind!.lowercased()))
    }

    private static func validOptionalUnitValue(_ value: Double?) -> Bool {
        guard let value else { return true }
        return value.isFinite && (0...1.1).contains(value)
    }

    private static func validOptionalSpeed(_ value: Double?) -> Bool {
        guard let value else { return true }
        return value.isFinite && (0...10).contains(value)
    }

    private static func validOptionalPhase(_ value: Double?) -> Bool {
        guard let value else { return true }
        return value.isFinite && abs(value) <= 10_000
    }

    private static func validElement(_ element: ARIADiagramSpec.CanvasScene.Element, controlIDs: Set<String>) -> Bool {
        guard !element.id.isEmpty,
              supportedElementKinds.contains(element.kind.lowercased()),
              validOptionalCoordinate(element.x),
              validOptionalCoordinate(element.y),
              validOptionalCoordinate(element.x2),
              validOptionalCoordinate(element.y2),
              validOptionalUnitValue(element.width),
              validOptionalUnitValue(element.height),
              validOptionalUnitValue(element.radius),
              validOptionalUnitValue(element.amplitude),
              validOptionalSpeed(element.speed),
              validOptionalPhase(element.phase),
              (element.points?.count ?? 0) <= 256,
              element.points?.allSatisfy(validPoint) ?? true,
              element.animation.map({ supportedAnimations.contains($0.lowercased()) }) ?? true else {
            return false
        }
        let references = [element.speedControl, element.amplitudeControl, element.radiusControl, element.visibilityControl].compactMap { $0 }
        return references.allSatisfy(controlIDs.contains)
    }
}

nonisolated struct ARIADiagramSpec: Codable, Equatable, Sendable {
    struct Series: Codable, Equatable, Sendable {
        let label: String?
        let color: String?
        let points: [[Double]]

        init(label: String?, color: String?, points: [[Double]]) {
            self.label = label
            self.color = color
            self.points = points
        }
    }

    struct Node: Codable, Equatable, Sendable {
        let id: String
        let label: String
        let x: Double?
        let y: Double?
        let color: String?
    }

    struct Edge: Codable, Equatable, Sendable {
        let from: String
        let to: String
        let label: String?
    }

    struct CanvasScene: Codable, Equatable, Sendable {
        struct Element: Codable, Equatable, Sendable {
            let id: String
            let kind: String
            let x: Double?
            let y: Double?
            let x2: Double?
            let y2: Double?
            let width: Double?
            let height: Double?
            let radius: Double?
            let label: String?
            let color: String?
            let animation: String?
            let amplitude: Double?
            let speed: Double?
            let phase: Double?
            let speedControl: String?
            let amplitudeControl: String?
            let radiusControl: String?
            let visibilityControl: String?
            let points: [[Double]]?

            init(
                id: String,
                kind: String,
                x: Double?,
                y: Double?,
                x2: Double?,
                y2: Double?,
                width: Double?,
                height: Double?,
                radius: Double?,
                label: String?,
                color: String?,
                animation: String?,
                amplitude: Double?,
                speed: Double?,
                phase: Double?,
                speedControl: String?,
                amplitudeControl: String?,
                radiusControl: String?,
                visibilityControl: String?,
                points: [[Double]]? = nil
            ) {
                self.id = id
                self.kind = kind
                self.x = x
                self.y = y
                self.x2 = x2
                self.y2 = y2
                self.width = width
                self.height = height
                self.radius = radius
                self.label = label
                self.color = color
                self.animation = animation
                self.amplitude = amplitude
                self.speed = speed
                self.phase = phase
                self.speedControl = speedControl
                self.amplitudeControl = amplitudeControl
                self.radiusControl = radiusControl
                self.visibilityControl = visibilityControl
                self.points = points
            }
        }

        struct Control: Codable, Equatable, Sendable {
            let id: String
            let label: String
            let min: Double
            let max: Double
            let value: Double
            let unit: String?
            let kind: String?
        }

        let elements: [Element]
        let controls: [Control]?
    }

    let type: String
    let title: String?
    let xLabel: String?
    let yLabel: String?
    let series: [Series]?
    let nodes: [Node]?
    let edges: [Edge]?
    let simulation: String?
    let particleCount: Int?
    let canvas: CanvasScene?

    init(
        type: String,
        title: String?,
        xLabel: String?,
        yLabel: String?,
        series: [Series]?,
        nodes: [Node]?,
        edges: [Edge]?,
        simulation: String? = nil,
        particleCount: Int? = nil,
        canvas: CanvasScene? = nil
    ) {
        self.type = type
        self.title = title
        self.xLabel = xLabel
        self.yLabel = yLabel
        self.series = series
        self.nodes = nodes
        self.edges = edges
        self.simulation = simulation
        self.particleCount = particleCount
        self.canvas = canvas
    }

    var isFlow: Bool { type.caseInsensitiveCompare("flow") == .orderedSame }
    var isSimulation: Bool { type.caseInsensitiveCompare("simulation") == .orderedSame }
    var isCanvas: Bool { type.caseInsensitiveCompare("canvas") == .orderedSame }
    var graphSeries: [Series] { series ?? [] }
    var flowNodes: [Node] { nodes ?? [] }
    var flowEdges: [Edge] { edges ?? [] }
}
