import QtQuick

// Audio-reactive layered waves. MediaWidget owns the cava process and the
// smoothed values; this only draws. `frame` is a repaint doorbell — the owner
// bumps it each lerp tick and the canvas redraws with the current vals. A
// property binding is used instead of calling requestPaint() across ids
// because items nested in Quickshell's ClippingRectangle get their own
// creation context, where outer document ids silently fail to resolve
// (ReferenceError at runtime, fine at load).
Canvas {
    id: root

    property var theme
    property var vals: []
    property int frame: 0
    // Corner rounding baked into the clip path — the canvas is rectangular,
    // the pills and cards it sits on are not.
    property real topRadius: 0
    property real bottomRadius: 0
    // Scales every band's alpha; the pill runs dimmer than the popup so the
    // text on top stays legible.
    property real alphaScale: 1

    onFrameChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const w = width, h = height;
        const v = root.vals, n = v.length;
        if (n < 2 || !root.theme) return;

        const rt = root.topRadius, rb = root.bottomRadius;
        ctx.beginPath();
        ctx.moveTo(rt, 0);
        ctx.lineTo(w - rt, 0);
        if (rt > 0) ctx.arcTo(w, 0, w, rt, rt);
        ctx.lineTo(w, h - rb);
        if (rb > 0) ctx.arcTo(w, h, w - rb, h, rb);
        ctx.lineTo(rb, h);
        if (rb > 0) ctx.arcTo(0, h, 0, h - rb, rb);
        ctx.lineTo(0, rt);
        if (rt > 0) ctx.arcTo(0, 0, rt, 0, rt);
        ctx.closePath();
        ctx.clip();

        // Smooth curve through the bar points: quadratics through segment
        // midpoints, filled to the bottom edge.
        function band(scale, phase, color, topA, botA) {
            const pts = [];
            for (let i = 0; i < n; i++) {
                const j = (i + phase) % n;
                pts.push({ x: w * i / (n - 1),
                           y: h - 2 - (v[j] / 7) * (h - 6) * scale });
            }
            ctx.beginPath();
            ctx.moveTo(0, h);
            ctx.lineTo(pts[0].x, pts[0].y);
            for (let i = 0; i < n - 1; i++)
                ctx.quadraticCurveTo(pts[i].x, pts[i].y,
                                     (pts[i].x + pts[i + 1].x) / 2,
                                     (pts[i].y + pts[i + 1].y) / 2);
            ctx.lineTo(w, pts[n - 1].y);
            ctx.lineTo(w, h);
            ctx.closePath();
            const g = ctx.createLinearGradient(0, 0, 0, h);
            g.addColorStop(0, Qt.alpha(color, topA * root.alphaScale));
            g.addColorStop(1, Qt.alpha(color, botA * root.alphaScale));
            ctx.fillStyle = g;
            ctx.fill();
        }

        // Back to front; phase offsets desync the layers so they read as
        // depth rather than one shape traced three times.
        band(0.45, 8, root.theme.accent2, 0.30, 0.02);
        band(0.70, 4, root.theme.accent, 0.35, 0.03);
        band(1.00, 0, Qt.rgba(0.114, 0.725, 0.329, 1), 0.55, 0.04);
    }
}
