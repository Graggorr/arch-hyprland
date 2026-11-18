import QtQuick
import QtQuick.Shapes

// The notch's silhouette: a flat top welded to the screen edge, concave
// "ears" flaring out into the bezel at both top corners, and rounded bottom
// corners. The item is the body plus an ear on each side, so whoever places
// it offsets x by -ear to line the body up with what it wraps.
//
// Quadratic curves rather than true arcs, as the macOS notch apps draw it:
// at these sizes the difference is invisible and every radius can animate
// without the path ever going degenerate.
Shape {
    id: root

    property real bodyWidth: 200
    property real bodyHeight: 32
    property real ear: 10
    property real radius: 14
    property color topColor: "black"
    property color bottomColor: "black"
    // A hairline along the sides and bottom only — never the top, which
    // must melt into the bezel.
    property color edgeColor: "transparent"

    readonly property real e: Math.max(0, Math.min(ear, bodyHeight / 2))
    readonly property real r: Math.max(0, Math.min(radius, bodyHeight - e, bodyWidth / 2))

    width: bodyWidth + 2 * e
    height: bodyHeight
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: -1
        fillGradient: LinearGradient {
            x1: 0; y1: 0; x2: 0; y2: root.height
            GradientStop { position: 0; color: root.topColor }
            GradientStop { position: 1; color: root.bottomColor }
        }

        startX: 0; startY: 0
        PathLine { x: root.width; y: 0 }
        PathQuad { x: root.width - root.e; y: root.e; controlX: root.width - root.e; controlY: 0 }
        PathLine { x: root.width - root.e; y: root.height - root.r }
        PathQuad { x: root.width - root.e - root.r; y: root.height; controlX: root.width - root.e; controlY: root.height }
        PathLine { x: root.e + root.r; y: root.height }
        PathQuad { x: root.e; y: root.height - root.r; controlX: root.e; controlY: root.height }
        PathLine { x: root.e; y: root.e }
        PathQuad { x: 0; y: 0; controlX: root.e; controlY: 0 }
    }

    ShapePath {
        strokeWidth: root.edgeColor.a > 0 ? 1 : 0
        strokeColor: root.edgeColor
        fillColor: "transparent"
        startX: root.width - root.e - 0.5; startY: root.e
        PathLine { x: root.width - root.e - 0.5; y: root.height - root.r }
        PathQuad { x: root.width - root.e - root.r; y: root.height - 0.5; controlX: root.width - root.e - 0.5; controlY: root.height - 0.5 }
        PathLine { x: root.e + root.r; y: root.height - 0.5 }
        PathQuad { x: root.e + 0.5; y: root.height - root.r; controlX: root.e + 0.5; controlY: root.height - 0.5 }
        PathLine { x: root.e + 0.5; y: root.e }
    }
}
