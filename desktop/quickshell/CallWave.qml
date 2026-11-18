import QtQuick

// The phone's call waveform, as it actually is: one cluster of thin rounded
// bars mirrored about the centre line, scrolling right-to-left as a time
// history of the conversation — each bar is a moment, coloured by who was
// speaking in it. The other side wears the theme's primary, your own voice its
// tertiary, so a glance at the island tells you who has been doing the
// talking. Silence leaves a row of dots, the way the phone idles.
Canvas {
    id: root

    // Current loudness of each side, 0..1, lerped by the owner.
    property real them: 0
    property real me: 0
    // Repaint doorbell, bumped by the owner's lerp tick; every third bump
    // pushes a new bar so the history spans a second or two, not a blink.
    property int frame: 0
    property color colorThem: "#30d158"
    property color colorMe: "#ff9f0a"
    property int bars: 16

    property var history: []
    property int tick: 0

    onFrameChanged: {
        root.tick++;
        if (root.tick % 3 === 0) {
            const h = root.history.slice();
            const level = Math.max(root.them, root.me);
            h.push({ level: level, mine: root.me > root.them * 1.15 && root.me > 0.08 });
            while (h.length > root.bars) h.shift();
            root.history = h;
        }
        requestPaint();
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const w = width, h = height;
        const bw = 2;
        const gap = (w - root.bars * bw) / (root.bars - 1);
        const mid = h / 2;
        const hist = root.history;
        const offset = root.bars - hist.length;

        for (let i = 0; i < root.bars; i++) {
            const k = i - offset;
            const s = k >= 0 ? hist[k] : null;
            const level = s ? Math.max(0, Math.min(1, s.level)) : 0;
            // never below a dot: the phone's idle row
            const bh = Math.max(bw, level * (h - 2));
            const x = i * (bw + gap);
            ctx.fillStyle = s && s.mine ? root.colorMe : root.colorThem;
            ctx.globalAlpha = s ? 1 : 0.55;
            ctx.beginPath();
            ctx.roundedRect(x, mid - bh / 2, bw, bh, bw / 2, bw / 2);
            ctx.fill();
        }
        ctx.globalAlpha = 1;
    }
}
