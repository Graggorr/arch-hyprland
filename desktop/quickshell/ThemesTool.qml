import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// The theme switcher, as an island face tool (Super+W): a search field over
// a list of the colour themes (~/.config/hypr/themes.json). Each row is
// drawn in its own theme — its surface, its swatches, its accent — so the
// list previews itself. Enter puts the theme on the chosen
// scope with wallpapers from that theme; the full wallpaper browser of a
// theme (ThemeSwitcher) is Ctrl+B away.
//
// Keyboard first like the launcher: type to filter, ↑/↓ (or Tab) to move,
// Enter applies, Ctrl+M changes the scope, Esc closes. Applying keeps the
// card open so you can watch the shell repaint and try the next one.
Item {
    id: root

    property var theme

    readonly property string script: "@HOME@/.config/hypr/scripts/wallpapers.py"

    property var themes: []
    property var applied: ({})
    property string system: "mono"
    property string target: "all"
    property string query: ""
    property int selected: 0
    property string applying: ""
    // Off until the first list lands, so the carousel opens already on the
    // worn theme instead of sliding there from the first card.
    property bool settled: false

    readonly property var outputs: {
        const all = Array.from(Quickshell.screens);
        all.sort((a, b) => a.x - b.x || a.y - b.y);
        return all.map(s => s.name);
    }

    function themeOf(output) {
        const e = root.applied[output];
        return e && e.theme ? e.theme : root.system;
    }
    function worn(id) {
        if (root.target !== "all") return root.themeOf(root.target) === id;
        for (let i = 0; i < root.outputs.length; i++)
            if (root.themeOf(root.outputs[i]) !== id) return false;
        return root.outputs.length > 0;
    }

    readonly property var results: {
        const q = root.query.trim().toLowerCase();
        if (q === "") return root.themes;
        const qv = IslandState.searchVariants(q);
        return root.themes.filter(t => IslandState.searchHit(t.name + " " + t.id, qv));
    }
    onResultsChanged: if (selected >= results.length) selected = Math.max(0, results.length - 1)
    // Kept in step both ways by hand: a flick on the carousel moves its own
    // currentIndex, which would silently break a declarative binding.
    onSelectedChanged: if (carousel.currentIndex !== selected) carousel.currentIndex = selected

    function reload() {
        root.settled = false;
        root.query = "";
        root.target = "all";
        search.text = "";
        lister.running = true;
        search.forceActiveFocus();
    }

    // Through the list, which wraps: a step past either end lands on the
    // other one.
    function moveSelection(delta) {
        if (root.results.length === 0) return;
        if (delta > 0) carousel.incrementCurrentIndex();
        else carousel.decrementCurrentIndex();
    }

    function cycleTarget() {
        const opts = ["all"].concat(root.outputs);
        root.target = opts[(opts.indexOf(root.target) + 1) % opts.length];
    }

    function apply(i) {
        if (i < 0 || i >= root.results.length) return;
        const t = root.results[i];
        root.applying = t.id;
        setter.command = ["python3", root.script, "apply", root.target, t.id];
        setter.running = true;
    }

    function browse(i) {
        if (i < 0 || i >= root.results.length) return;
        const id = root.results[i].id;
        IslandState.closeCard();
        IslandState.openWallpapers(id);
    }

    Process {
        id: lister
        command: ["python3", root.script, "theme-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.themes = JSON.parse(text).themes; } catch (e) { root.themes = []; }
                for (let i = 0; i < root.results.length; i++)
                    if (root.worn(root.results[i].id)) { root.selected = i; break; }
                carousel.currentIndex = root.selected;
                Qt.callLater(() => root.settled = true);
            }
        }
    }

    Process { id: setter }

    FileView {
        path: "@HOME@/.config/hypr/wallpapers.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.applied = JSON.parse(text()) || {}; } catch (e) { root.applied = {}; }
        }
    }
    FileView {
        path: "@HOME@/.config/hypr/theme.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.system = JSON.parse(text()).system || "mono"; } catch (e) { }
        }
    }

    // The palette pass runs detached and takes a moment; the busy dot clears
    // on its own once the repaint has had time to land.
    Timer { interval: 2500; running: root.applying !== ""; onTriggered: root.applying = "" }

    Rectangle {
        id: searchBox
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 12
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        height: 40
        radius: 12
        color: Qt.alpha(root.theme.on_surface, 0.05)
        border.width: 1
        border.color: Qt.alpha(root.theme.on_surface, search.activeFocus ? 0.12 : 0.07)

        Text {
            id: searchGlyph
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{f0349}"
            font.family: root.theme.fontMono
            font.pixelSize: 15
            color: Qt.alpha(root.theme.on_surface_variant, 0.8)
        }

        TextInput {
            id: search
            anchors.left: searchGlyph.right
            anchors.leftMargin: 10
            anchors.right: countLabel.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            onTextChanged: { root.query = text; root.selected = 0; }
            color: root.theme.on_surface
            font.family: root.theme.fontSans
            font.pixelSize: IslandState.ts(14)
            selectionColor: Qt.alpha(root.theme.primary, 0.35)
            selectByMouse: true
            clip: true

            Text {
                anchors.fill: parent
                visible: search.text === ""
                text: "Search themes…"
                color: Qt.alpha(root.theme.on_surface_variant, 0.65)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(14)
                verticalAlignment: Text.AlignVCenter
            }

            Keys.onEscapePressed: (e) => { IslandState.closeCard(); e.accepted = true; }
            Keys.onReturnPressed: root.apply(root.selected)
            Keys.onEnterPressed: root.apply(root.selected)
            Keys.onDownPressed: root.moveSelection(1)
            Keys.onUpPressed: root.moveSelection(-1)
            Keys.onRightPressed: root.moveSelection(1)
            Keys.onLeftPressed: root.moveSelection(-1)
            Keys.onPressed: (e) => {
                const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                if (e.key === Qt.Key_Tab) { root.moveSelection(1); e.accepted = true; }
                else if (e.key === Qt.Key_Backtab) { root.moveSelection(-1); e.accepted = true; }
                else if (ctrl && e.key === Qt.Key_M) { root.cycleTarget(); e.accepted = true; }
                else if (ctrl && e.key === Qt.Key_B) { root.browse(root.selected); e.accepted = true; }
            }
        }

        Text {
            id: countLabel
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: root.results.length ? (root.selected + 1) + "/" + root.results.length : "0"
            color: Qt.alpha(root.theme.on_surface_variant, 0.65)
            font.family: root.theme.fontSans
            font.pixelSize: IslandState.ts(12)
        }
    }

    // A list, the way the launcher is one: the selected theme opens into a
    // tall row that shows the wallpaper it last wore on its right, its name
    // in the display face and its swatches under the name; the rest stay
    // thin rows with a colour chip and their swatches at the far edge. Each
    // row wears its own theme's surface and accent, so the list previews
    // itself while you scroll it.
    ListView {
        id: carousel

        readonly property real thin: 34
        readonly property real tall: 70

        anchors.top: searchBox.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.bottom: hint.top
        anchors.bottomMargin: 10
        model: root.results
        clip: true
        spacing: 2
        keyNavigationWraps: true
        boundsBehavior: Flickable.StopAtBounds
        highlightFollowsCurrentItem: false
        onCurrentIndexChanged: {
            if (currentIndex !== root.selected) root.selected = currentIndex;
            settle.restart();
        }
        // The rows resize as the selection moves, so where the selected row
        // ends up is only known once that settles.
        Timer {
            id: settle
            interval: root.settled ? 200 : 0
            onTriggered: carousel.positionViewAtIndex(carousel.currentIndex, ListView.Contain)
        }

        delegate: Item {
            id: slot
            required property var modelData
            required property int index
            readonly property bool isSelected: index === root.selected
            readonly property bool isWorn: root.worn(modelData.id)
            readonly property bool hasWall: (modelData.wallpaper || "") !== ""
            // Follows selection with a short lag, so holding an arrow key
            // never stacks half-run animations: a row that is passed over
            // just reverses from wherever it was.
            property real reveal: isSelected ? 1 : 0
            Behavior on reveal {
                enabled: root.settled
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }

            width: ListView.view.width
            height: carousel.thin + (carousel.tall - carousel.thin) * reveal

            Rectangle {
                id: tile
                anchors.fill: parent
                radius: 12 + 2 * slot.reveal
                color: slot.reveal > 0.01
                       ? Qt.rgba(slot.modelData.surfaceHigh.r, slot.modelData.surfaceHigh.g,
                                 slot.modelData.surfaceHigh.b, slot.reveal)
                       : (hov.hovered ? Qt.alpha(root.theme.on_surface, 0.05) : "transparent")
                border.width: slot.reveal > 0.5 ? 1 : 0
                border.color: Qt.alpha(slot.modelData.primary, 0.45)
            }

            // The wallpaper fills the right half and dissolves into the row
            // on its left edge rather than ending in a hard seam.
            ClippingRectangle {
                id: wall
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 1
                width: parent.width * 0.5
                radius: tile.radius - 1
                color: "transparent"
                visible: slot.reveal > 0.01 && slot.hasWall
                property string src: slot.modelData.wallpaper || ""
                property real shown: slot.reveal
                property color base: slot.modelData.surfaceHigh

                Image {
                    anchors.fill: parent
                    source: wall.src !== "" ? "file://" + wall.src : ""
                    sourceSize.width: 360
                    asynchronous: true
                    cache: true
                    fillMode: Image.PreserveAspectCrop
                    opacity: status === Image.Ready ? wall.shown : 0
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * 0.55
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: wall.base }
                        GradientStop { position: 1.0; color: Qt.rgba(wall.base.r, wall.base.g, wall.base.b, 0) }
                    }
                }
            }

            // Thin rows lead with a chip of the theme's primary; the tall row
            // drops it, the way a selected item needs no bullet.
            Rectangle {
                id: chip
                x: 9
                anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20; radius: 7
                color: Qt.alpha(slot.modelData.primary, 0.20)
                opacity: 1 - slot.reveal
                scale: 1 - 0.4 * slot.reveal
                visible: opacity > 0.01
                Rectangle {
                    anchors.centerIn: parent
                    width: 8; height: 8; radius: 4
                    color: slot.modelData.primary
                    SequentialAnimation on scale {
                        running: root.applying === slot.modelData.id
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { to: 0.4; duration: 380 }
                        NumberAnimation { to: 1; duration: 380 }
                    }
                }
            }

            Text {
                id: nameText
                readonly property real thinX: 40
                readonly property real tallX: 16
                readonly property real thinY: (carousel.thin - height) / 2
                readonly property real tallY: 13
                x: thinX + (tallX - thinX) * slot.reveal
                y: thinY + (tallY - thinY) * slot.reveal
                text: slot.modelData.name.toLowerCase()
                color: slot.isSelected ? Qt.lighter(slot.modelData.primary, 1.3)
                                       : slot.modelData.text
                font.family: slot.isSelected ? root.theme.fontDisplay : root.theme.fontSans
                font.pixelSize: slot.isSelected ? 18 : 12
                font.weight: slot.isSelected ? Font.Bold : Font.Normal
            }
            Text {
                anchors.left: nameText.right
                anchors.leftMargin: 8
                anchors.baseline: nameText.baseline
                visible: slot.isWorn
                text: "in use"
                color: Qt.alpha(slot.modelData.text, 0.6)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(10)
            }

            Row {
                id: dots
                readonly property real thinX: slot.width - width - 14
                readonly property real tallX: 16
                readonly property real thinY: (carousel.thin - height) / 2
                readonly property real tallY: carousel.tall - 14 - height
                x: thinX + (tallX - thinX) * slot.reveal
                y: thinY + (tallY - thinY) * slot.reveal
                spacing: 4 + 2 * slot.reveal

                Repeater {
                    model: slot.modelData.swatches
                    Rectangle {
                        required property string modelData
                        readonly property real d: 7 + 4 * slot.reveal
                        width: d; height: d; radius: d / 2
                        color: modelData
                    }
                }
            }

            HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (slot.isSelected) root.apply(slot.index);
                    else carousel.currentIndex = slot.index;
                }
            }
        }
    }

    Text {
        anchors.centerIn: carousel
        visible: root.results.length === 0 && root.themes.length > 0
        text: "Nothing matches"
        color: Qt.alpha(root.theme.on_surface_variant, 0.7)
        font.family: root.theme.fontSans
        font.pixelSize: IslandState.ts(12)
    }

    // Where Enter lands. Hidden on a single monitor, where it means nothing.
    Row {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: hint.verticalCenter
        spacing: 4
        visible: root.outputs.length > 1

        Repeater {
            model: ["all"].concat(root.outputs)

            Rectangle {
                id: chip
                required property var modelData
                readonly property bool active: root.target === modelData
                width: chipLabel.implicitWidth + 16
                height: 22
                radius: 7
                color: chip.active ? Qt.alpha(root.theme.on_surface, 0.10) : "transparent"
                Behavior on color { ColorAnimation { duration: 110 } }
                Text {
                    id: chipLabel
                    anchors.centerIn: parent
                    text: chip.modelData === "all" ? "All monitors" : chip.modelData
                    color: chip.active ? root.theme.on_surface
                                       : Qt.alpha(root.theme.on_surface_variant, 0.6)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(11)
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.target = chip.modelData
                }
            }
        }
    }

    Text {
        id: hint
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 16
        anchors.bottomMargin: 14
        text: "Ctrl+B wallpapers     Enter to apply"
        color: Qt.alpha(root.theme.on_surface_variant, 0.6)
        font.family: root.theme.fontSans
        font.pixelSize: IslandState.ts(11)
    }
}
