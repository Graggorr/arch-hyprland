#version 440
// hyprglass backdrop emulation for the lock screen. Every visual term is
// scaled by a uniform parsed live out of hyprland.lua's hg.preset("main")
// block by LockContent.qml — the numeric constants here only set how much one
// unit of each preset knob is worth on a full-screen pane, so the lock tracks
// the desktop glass as the preset changes.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float refraction;
    float aberration;
    float fresnel;
    float specular;
    float edge;
    float lens;
} ubuf;
layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 c = uv - 0.5;
    float r2 = dot(c, c);

    // barrel lens distortion, strongest toward the corners
    vec2 lensUv = vec2(0.5) + c * (1.0 + ubuf.lens * 0.15 * r2);

    // refraction: on a full-screen pane the real plugin shows no wavy line
    // displacement (verified against a fullscreen glass terminal 2026-09-11),
    // just a faint unevenness folded into the blur
    vec2 disp = vec2(sin(uv.y * 22.0 + uv.x * 7.0),
                     cos(uv.x * 22.0 - uv.y * 5.0)) * ubuf.refraction * 0.0015;
    vec2 suv = clamp(lensUv + disp, vec2(0.0), vec2(1.0));

    // chromatic aberration: radial channel split, calibrated against the
    // real plugin's rainbow fringing (strong at corners, present mid-frame)
    vec2 ca = c * ubuf.aberration * (0.03 + 0.13 * r2);
    float rC = texture(source, clamp(suv + ca, vec2(0.0), vec2(1.0))).r;
    vec4 gC = texture(source, suv);
    float bC = texture(source, clamp(suv - ca, vec2(0.0), vec2(1.0))).b;
    vec3 col = vec3(rC, gC.g, bC);

    // fresnel rim: brighten within edge_thickness of the pane borders
    float dEdge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    float rim = 1.0 - smoothstep(0.0, max(ubuf.edge, 0.001), dEdge);
    col += rim * ubuf.fresnel * 0.08;

    // specular sheen: soft diagonal highlight band across the pane
    float band = exp(-pow((uv.x + uv.y - 0.7) * 2.6, 2.0));
    col += band * ubuf.specular * 0.02;

    fragColor = vec4(col, 1.0) * ubuf.qt_Opacity;
}
