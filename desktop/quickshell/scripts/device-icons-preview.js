const fs = require("fs");
const path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "DeviceIcons.js"), "utf8").replace(".pragma library", "");
const m = {};
new Function("exports", src + "\nexports.icons = icons;")(m);
const kinds = Object.keys(m.icons);
const tints = { dualsense: ["#eae6ef", "#f2a2c4", "#f2f2f0"], xbox: ["#eae6ef", "#5b8fe0"] };
const cellW = 200, rowH = 150;
let body = "";
kinds.forEach((k, i) => {
  const ic = m.icons[k];
  const y = i * rowH;
  const glyph = (x, yy, size, col) =>
    `<g transform="translate(${x},${yy}) scale(${size / ic.grid})">` +
    `<path d="${ic.d}" fill="${col}" fill-rule="${ic.rule}"/></g>`;
  body += `<text x="16" y="${y + 80}" font-family="JetBrainsMono Nerd Font" font-size="18" fill="#cfc8d8">${k}</text>`;
  body += glyph(170, y + 15, 120, "#eae6ef");
  body += glyph(320, y + 55, 36, "#eae6ef");
  body += `<rect x="380" y="${y + 58}" width="120" height="30" rx="8" fill="#2f2938"/>`;
  body += glyph(390, y + 65, 17, "#eae6ef");
  body += `<text x="412" y="${y + 79}" font-family="JetBrainsMono Nerd Font" font-size="13" fill="#eae6ef">95%</text>`;
  (tints[k] || []).slice(1).forEach((c, j) => { body += glyph(530 + j * 60, y + 55, 36, c); });
});
const W = 700, H = kinds.length * rowH;
fs.writeFileSync(process.argv[2],
  `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}"><rect width="100%" height="100%" fill="#1d1922"/>${body}</svg>`);
