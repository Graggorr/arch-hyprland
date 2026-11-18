import QtQuick
import QtQuick.Shapes

// Nerd Fonts 3.5.0 has no Ghostty glyph (only `dev-ghost`, the blogging
// platform), so the mark is carried as vector path data instead of a codepoint.
// It is the ghost from Papirus' com.mitchellh.ghostty-symbolic with the outer
// terminal-window rect dropped — at 18px that rect collided with the
// workspace button's own rounded highlight and buried the ghost inside it.
//
// One subpath is the ghost body, two are the `>` and `_` of the prompt; they
// read as knockouts purely from OddEvenFill, so the whole mark is a single
// fill and tints/animates like the font glyphs next to it.
//
// Path coordinates live in the source 24x24 box, where the ghost occupies
// 7,7 -> 17,17. Translate then scale maps that 10-unit box onto `size`.
Item {
    id: root

    property color color: "white"
    property real size: 18

    implicitWidth: size
    implicitHeight: size

    Shape {
        width: 24
        height: 24
        preferredRendererType: Shape.CurveRenderer
        transform: [
            Translate { x: -7; y: -7 },
            Scale { xScale: root.size / 10; yScale: root.size / 10 }
        ]

        ShapePath {
            fillColor: root.color
            fillRule: ShapePath.OddEvenFill
            strokeWidth: -1

            Behavior on fillColor { ColorAnimation { duration: 130 } }

            PathSvg {
                path: "M 12.0,7.000019 c 2.76113,0 5,2.101 5,5 v 3.22266 c 0,0.933323 -0.686451,1.72605 -1.57422,1.77734 -0.431111,0.02448 -0.82893,-0.124552 -1.13672,-0.384766 -0.368876,-0.311387 -0.88752,-0.298276 -1.25977,0.0098 -0.283331,0.2345 -0.641231,0.375 -1.03125,0.375 -0.390024,0 -0.745965,-0.1405 -1.0293,-0.375 -0.376645,-0.311488 -0.894831,-0.311488 -1.27148,0 -0.28111,0.232176 -0.635058,0.3727 -1.01953,0.375 -0.923305,0.007 -1.67773,-0.809796 -1.67773,-1.7793 v -3.2207 c 0,-2.89925 2.23911,-5 5,-5 z m -2.59766,3.00977 a 0.499989,0.499989 0 0 0 -0.318359,0.212891 0.500172,0.500172 0 0 0 0.138672,0.693359 l 0.875,0.583984 -0.875,0.583984 a 0.500162,0.500162 0 0 0 -0.138672,0.693359 0.500001,0.500001 0 0 0 0.693359,0.138672 l 1.14648,-0.765625 A 0.77737,0.77737 0 0 0 11.277356,11.507835 0.792144,0.792144 0 0 0 10.92384,10.849632 L 9.77736,10.084007 a 0.499989,0.499989 0 0 0 -0.375,-0.07422 z m 3.59766,0.990234 a 0.5,0.5 0 0 0 -0.5,0.5 0.5,0.5 0 0 0 0.5,0.5 h 1.5 a 0.5,0.5 0 0 0 0.5,-0.5 0.5,0.5 0 0 0 -0.5,-0.5 z"
            }
        }
    }
}
