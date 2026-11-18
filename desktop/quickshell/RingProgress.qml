import QtQuick

// Circular progress for the trailing capsule. Canvas rather than a Shape
// because the rest of this config already draws with Canvas (WaveCanvas) and
// it keeps the QtQuick.Shapes dependency out of the bar.
Canvas {
    id: root

    property real progress: 0
    property color ring: "#f5a623"
    property color track: "#ffffff"
    property real trackAlpha: 0.16
    property real thickness: 2.5
    // Symmetric mode grows the arc from twelve o'clock down both sides at
    // once, head and tail meeting at the bottom when full — the status
    // circle's battery. The default stays the clockwise timer dial.
    property bool symmetric: false

    onProgressChanged: requestPaint()
    onRingChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    // The status circle binds track to the live palette while the ring can sit
    // on the fixed charging green — a retheme must repaint even when neither
    // progress nor ring moved.
    onTrackChanged: requestPaint()
    onTrackAlphaChanged: requestPaint()
    onThicknessChanged: requestPaint()
    onSymmetricChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();

        const r = Math.min(width, height) / 2 - root.thickness / 2;
        if (r <= 0) return;
        const cx = width / 2, cy = height / 2;

        ctx.lineWidth = root.thickness;
        ctx.lineCap = "round";

        ctx.strokeStyle = Qt.alpha(root.track, root.trackAlpha);
        ctx.beginPath();
        ctx.arc(cx, cy, r, 0, Math.PI * 2);
        ctx.stroke();

        if (root.progress <= 0) return;
        const p = Math.min(1, root.progress);
        ctx.strokeStyle = root.ring;
        ctx.beginPath();
        if (root.symmetric)
            ctx.arc(cx, cy, r, -Math.PI / 2 - Math.PI * p, -Math.PI / 2 + Math.PI * p);
        else
            // Twelve o'clock start, clockwise, like every timer dial.
            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * p);
        ctx.stroke();
    }
}
