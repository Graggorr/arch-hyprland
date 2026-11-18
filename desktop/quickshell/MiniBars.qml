import QtQuick

// The phone-island waveform: a handful of discrete rounded bars dancing on
// the cava values. WaveCanvas draws moody layered curves for big surfaces;
// this is its 30px sibling for the pill ends.
Canvas {
    id: root

    property var vals: []
    property int frame: 0
    property color color: "#1db954"
    // Five at the resting 27px; a wider canvas (the island granting it the
    // short side's slack) gains bars at the same pitch instead of gaps.
    property int bars: Math.max(5, Math.floor((width + 3) / 6))

    onFrameChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const w = width, h = height;
        const v = root.vals, n = v.length;
        if (n < 1) return;

        const bw = 3;
        const gap = (w - root.bars * bw) / (root.bars - 1);
        ctx.fillStyle = root.color;

        for (let i = 0; i < root.bars; i++) {
            // Spread the sample points across the 12 cava bands.
            const j = Math.min(n - 1, Math.round(i * (n - 1) / (root.bars - 1)));
            const level = Math.max(0, Math.min(1, v[j] / 7));
            const bh = Math.max(bw, level * h);
            const x = i * (bw + gap);
            const y = (h - bh) / 2;
            ctx.beginPath();
            ctx.roundedRect(x, y, bw, bh, bw / 2, bw / 2);
            ctx.fill();
        }
    }
}
