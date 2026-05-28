/*
    SPDX-FileCopyrightText: 2013 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2014 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2019-2020 Konrad Materka <materka@gmail.com>
    SPDX-FileCopyrightText: 2022 ivan (@ratijas) tkachenko <me@ratijas.tk>
    SPDX-FileCopyrightText: 2025 Kristen McWilliam <kristen@kde.org>
    SPDX-FileCopyrightText: 2025 Nate Graham <nate@kde.org>
    SPDX-FileCopyrightText: 2026 Nathaniel Krebs <areyoufeelingitnowmrkrebs@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window

import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels
import org.kde.kquickcontrols as KQC
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

KCMUtils.ScrollViewKCM {
    id: iconsPage

    signal configurationChanged
    property bool unsavedChanges: !(changedVisibility.size === 0 && changedShortcuts.size === 0)

    property bool cfg_scaleIconsToFit
    property int cfg_iconSpacing
    property bool cfg_reverseIconOrder
    property string cfg_orderingMode: "direction"
    property bool cfg_respectDirection: false
    property bool cfg_showAllItems
    property list<string> cfg_shownItems: []
    property list<string> cfg_hiddenItems: []
    property list<string> cfg_extraItems: []
    property list<string> cfg_disabledStatusNotifiers: []

    // We can share one combobox model across all delegates, they all have the same options
    readonly property var comboBoxModel: {
        const autoElement = {
            "value": "auto",
            "text": i18nc("@item:inlistbox Show this System Tray item when relevant", "Show when relevant") // qmllint disable unqualified
        };
        const shownElement = {
            "value": "shown",
            "text": i18nc("@item:inlistbox Always show this System Tray item", "Always show") // qmllint disable unqualified
        };
        const hiddenElement = {
            "value": "hidden",
            "text": i18nc("@item:inlistbox Show this System Tray item only in the expanded popup", "Show only in popup") // qmllint disable unqualified
        };
        const disabledElement = {
            "value": "disabled",
            "text": i18nc("@item:inlistbox Never show this System Tray item; disable it", "Never show (disabled)") // qmllint disable unqualified
        };

        return cfg_showAllItems ? [autoElement, disabledElement] : [autoElement, shownElement, hiddenElement, disabledElement];
    }

    readonly property var changedShortcuts: new Map()
    readonly property var changedVisibility: new Map()

    function saveConfig() {
        for (const [key, value] of changedVisibility.entries()) {
            updateVisibility(key, value);
        }
        for (const [key, value] of changedShortcuts.entries()) {
            key.globalShortcut = value;
        }
        changedShortcuts.clear();
        changedVisibility.clear();
        cfg_shownItemsChanged();
        cfg_hiddenItemsChanged();
        cfg_extraItemsChanged();
        cfg_disabledStatusNotifiersChanged();
        changedShortcutsChanged();
        changedVisibilityChanged();
    }

    function updateVisibility(itemId: string, visibility: string): void {
        const shownIndex = cfg_shownItems.indexOf(itemId);
        const hiddenIndex = cfg_hiddenItems.indexOf(itemId);
        const extraIndex = cfg_extraItems.indexOf(itemId);
        const disabledSniIndex = cfg_disabledStatusNotifiers.indexOf(itemId);

        if (shownIndex > -1) {
            cfg_shownItems.splice(shownIndex, 1);
        }
        if (hiddenIndex > -1) {
            cfg_hiddenItems.splice(hiddenIndex, 1);
        }
        if (extraIndex > -1) {
            cfg_extraItems.splice(extraIndex, 1);
        }
        if (disabledSniIndex > -1) {
            cfg_disabledStatusNotifiers.splice(disabledSniIndex, 1);
        }

        switch (visibility) {
        case "auto":
        case "auto-sni":
            cfg_extraItems.push(itemId);
            break;
        case "shown":
            cfg_extraItems.push(itemId);
        /* fallthrough*/
        case "shown-sni":
            cfg_shownItems.push(itemId);
            break;
        case "hidden":
            cfg_extraItems.push(itemId);
        /* fallthrough */
        case "hidden-sni":
            cfg_hiddenItems.push(itemId);
            break;
        case "disabled-sni":
            cfg_disabledStatusNotifiers.push(itemId);
            break;
        }
    }

    function categoryName(category) {
        switch (category) {
        case "ApplicationStatus":
            return i18n("Application Status"); // qmllint disable unqualified
        case "Communications":
            return i18n("Communications"); // qmllint disable unqualified
        case "SystemServices":
            return i18n("System Services"); // qmllint disable unqualified
        case "Hardware":
            return i18n("Hardware Control"); // qmllint disable unqualified
        case "UnknownCategory":
        default:
            return i18n("Miscellaneous"); // qmllint disable unqualified
        }
    }

    Connections {
        target: Plasmoid.configSystemTrayModel
        function onRowsRemoved() {
            // if the user closes an app with a SNI that has a visibility change queued, we need to remove it
            // from the queue as the change is no longer visible in the UI.
            let idsToRemove = [...iconsPage.changedVisibility.keys()];
            for (let i = 0; i < Plasmoid.configSystemTrayModel.rowCount() && idsToRemove.length > 0; ++i) {
                let itemId = Plasmoid.configSystemTrayModel.index(i, 0).data(Qt.UserRole + 2);
                idsToRemove = idsToRemove.filter(id => id !== itemId);
            }
            idsToRemove.forEach(id => {
                iconsPage.changedVisibility.delete(id);
            });
            if (idsToRemove.length > 0) {
                iconsPage.changedVisibilityChanged();
            }
        }
    }

    header: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.InlineMessage {
            id: disablingSniMessage
            property string appName

            function showWithAppName(appName: string) {
                disablingSniMessage.appName = appName;
                visible = true;
            }

            Layout.fillWidth: true
            type: Kirigami.MessageType.Warning
            text: xi18nc("@info:usagetip", "Look for a setting in <application>%1</application> to disable its tray icon before doing it here. Some apps’ tray icons were not designed to be disabled, and using this setting may cause them to behave unexpectedly.<nl/><nl/>Use this setting at your own risk, and do not report issues to KDE or the app’s author.", appName) // qmllint disable unqualified
            actions: [
                Kirigami.Action {
                    text: i18nc("@action:button", "I understand the risks") // qmllint disable unqualified
                    onTriggered: disablingSniMessage.visible = false
                }
            ]
        }

        Kirigami.InlineMessage {
            id: disablingKlipperMessage

            visible: iconsPage.changedVisibility.get("org.kde.plasma.clipboard") === "disabled"
            Layout.fillWidth: true
            type: Kirigami.MessageType.Warning
            text: xi18nc("@info:usagetip", "Disabling the clipboard is not recommended, as it will cause copied data to be lost when the application it was copied from is closed.<nl/><nl/>Only do this if you’ve manually added a standalone Clipboard widget somewhere else, or are using a 3rd-party clipboard manager. Also, instead consider configuring the clipboard to not save history, or to only remember one item at a time.") // qmllint disable unqualified
        }

        Kirigami.InlineMessage {
            id: disablingNotificationsMessage

            visible: iconsPage.changedVisibility.get("org.kde.plasma.notifications") === "disabled"
            Layout.fillWidth: true
            type: Kirigami.MessageType.Warning
            text: xi18nc("@info:usagetip", "Disabling the Notifications widget is not recommended, as notifications sent by apps will no longer be shown.<nl/><nl/>Only do this if you’ve manually added a standalone Notifications widget somewhere else, or are intentionally using a 3rd-party notification manager to handle notifications.") // qmllint disable unqualified
        }

        Kirigami.FormLayout {
            id: formLayout

            readonly property int maxComboboxWidth: Math.max(sizeChooser.implicitWidth, spacingChooser.implicitWidth, layoutChooser.implicitWidth)

            QQC2.ComboBox {
                id: sizeChooser

                readonly property string scaleString: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
                    ? i18nc("@item:inlistbox Icon size", "Scale with Panel height")
                    : i18nc("@item:inlistbox Icon size", "Scale with Panel width")

                Kirigami.FormData.label: i18nc("@label:listbox Whether the system tray icons in the Panel always stay small or scale with the Panel's size", "Panel icon size:")
                Layout.preferredWidth: formLayout.maxComboboxWidth
                model: [
                    {
                        "label": i18nc("@item:inlistbox Icon size", "Small"),
                        "size": "small"
                    },
                    {
                        "label": scaleString,
                        "size": "scale"
                    }
                ]
                textRole: "label"

                currentIndex: iconsPage.cfg_scaleIconsToFit ? 1 : 0

                onActivated: index => {
                    iconsPage.cfg_scaleIconsToFit = model[currentIndex]["size"] == "scale";
                }
            }

            QQC2.ComboBox {
                id: spacingChooser

                Kirigami.FormData.label: i18nc("@label:listbox The spacing between system tray icons in the Panel", "Spacing:")
                Layout.preferredWidth: formLayout.maxComboboxWidth
                model: [
                    {
                        "label": i18nc("@item:inlistbox Icon spacing", "Small"),
                        "spacing": 1
                    },
                    {
                        "label": i18nc("@item:inlistbox Icon spacing", "Normal"),
                        "spacing": 2
                    },
                    {
                        "label": i18nc("@item:inlistbox Icon spacing", "Large"),
                        "spacing": 6
                    }
                ]
                textRole: "label"

                currentIndex: switch (iconsPage.cfg_iconSpacing) {
                    case 1: return 0; // Small
                    case 2: return 1; // Normal
                    case 6: return 2; // Large
                }

                onActivated: index => {
                    iconsPage.cfg_iconSpacing = model[currentIndex]["spacing"];
                }
            }

            QQC2.ComboBox {
                id: layoutChooser

                Kirigami.FormData.label: i18nc("@label:listbox Which direction system tray icons in the Panel emerge from the expander arrow", "Direction:")
                Layout.preferredWidth: formLayout.maxComboboxWidth

                textRole: "text"
                valueRole: "value"

                // Evaluate current system state for dynamic labels
                readonly property bool isRtl: Qt.application.layoutDirection === Qt.RightToLeft
                readonly property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

                model: {
                    if (isVertical) {
                        // Vertical default is arrow at bottom, expanding upwards
                        return [
                            { "text": i18n("Bottom-to-top"), "value": false },
                            { "text": i18n("Top-to-bottom"), "value": true }
                        ];
                    } else if (isRtl) {
                        // RTL default is arrow on left, expanding to the right
                        return [
                            { "text": i18n("Left-to-right"), "value": false },
                            { "text": i18n("Right-to-left"), "value": true }
                        ];
                    } else {
                        // Standard LTR default is arrow on right, expanding to the left
                        return [
                            { "text": i18n("Right-to-left"), "value": false },
                            { "text": i18n("Left-to-right"), "value": true }
                        ];
                    }
                }

                currentIndex: iconsPage.cfg_reverseIconOrder ? 1 : 0
                onActivated: iconsPage.cfg_reverseIconOrder = currentValue;
            }

            QQC2.CheckBox {
                id: customOrderCheck
                Kirigami.FormData.label: i18nc("@option:check", "Custom Order:")
                checked: iconsPage.cfg_orderingMode === "custom"
                onToggled: {
                    iconsPage.cfg_orderingMode = checked ? "custom" : "direction";
                }
            }
            QQC2.CheckBox {
                id: respectDirectionCheck
                enabled: customOrderCheck.checked
                checked: iconsPage.cfg_respectDirection
                text: i18nc("@option:check", "Respect Direction")
                leftPadding: Kirigami.Units.largeSpacing * 2
                onToggled: {
                    iconsPage.cfg_respectDirection = checked;
                }
            }

            QQC2.Label {
                visible: Kirigami.Settings.tabletMode
                text: i18nc("@info:usagetip under a combobox when Touch Mode is on", "Automatically set to Large when in Touch Mode")
                textFormat: Text.PlainText
                font: Kirigami.Theme.smallFont
            }
        }
    }

    view: ListView {
        id: itemsList

        property real keySequenceColumnWidth: Kirigami.Units.gridUnit
        readonly property int iconSize: Kirigami.Units.iconSizes.smallMedium

        clip: true

        model: KItemModels.KSortFilterProxyModel {
            id: sortFilterProxyModel
            filterCaseSensitivity: Qt.CaseInsensitive
            Component.onCompleted: sourceModel = Plasmoid.configSystemTrayModel // avoid unnecessary binding, it causes loops
        }
        reuseItems: true

        addDisplaced: Transition {
            NumberAnimation { properties: "y"; duration: 120; easing.type: Easing.OutQuad }
        }
        removeDisplaced: Transition {
            NumberAnimation { properties: "y"; duration: 120; easing.type: Easing.OutQuad }
        }

        Rectangle {
            id: dropIndicator
            visible: false
            height: 2
            width: itemsList.width - itemsList.leftMargin - itemsList.rightMargin
            x: itemsList.leftMargin
            color: Kirigami.Theme.highlightColor
            opacity: 0.8
            z: 999
            Component.onCompleted: parent = itemsList.contentItem
        }

        headerPositioning: ListView.OverlayHeader
        header: Kirigami.InlineViewHeader {
            width: itemsList.width
            text: i18nc("@title:column", "Entries")
            actions: [
                Kirigami.Action {
                    id: showAllCheckBox
                    text: i18nc("@option:check, This is referring to system tray entries", "Always show all") // qmllint disable unqualified
                    onToggled: iconsPage.cfg_showAllItems = checked
                    checked: iconsPage.cfg_showAllItems
                    displayComponent: QQC2.CheckBox {
                        horizontalPadding: Kirigami.Units.largeSpacing
                        text: showAllCheckBox.text
                        checked: showAllCheckBox.checked
                        onToggled: showAllCheckBox.toggle()
                    }
                },
                Kirigami.Action {
                    id: searchAction
                    property string searchText: ""
                    displayComponent: Kirigami.SearchField {
                        onTextChanged: {
                            // reset currentIndex to avoid passing focus to the currentItem when
                            // the model updates
                            itemsList.currentIndex = -1
                            sortFilterProxyModel.filterString = text
                        }
                    }
                }
            ]
        }

        section {
            property: "category"
            delegate: Kirigami.ListSectionHeader {
                required property string section

                text: iconsPage.categoryName(section)
                width: itemsList.width
            }
        }

        delegate: Item {
            id: delegateWrapper
            width: itemsList.width

            required property var applet
            required property var decoration
            required property string displayText
            required property int index
            required property string itemId
            required property string itemType

            height: dragItem.height
            clip: false

            TrayItemDelegate {
                id: dragItem
                applet: delegateWrapper.applet
                decoration: delegateWrapper.decoration
                displayText: delegateWrapper.displayText
                index: delegateWrapper.index
                itemId: delegateWrapper.itemId
                itemType: delegateWrapper.itemType
            }
        }
    }

    // Re-add separator line between footer and list view
    extraFooterTopPadding: true

    function computeGapIndex(viewportY: real): int {
        const count = sortFilterProxyModel.rowCount();
        if (count === 0) return 0;

        const index = itemsList.indexAt(1, viewportY);
        if (index < 0) {
            return viewportY < 0 ? 0 : count;
        }

        const item = itemsList.itemAtIndex(index);
        if (!item) return index;

        // item.y is in contentItem coordinates; convert to viewport
        const itemViewportY = item.y - itemsList.contentY;
        const midY = itemViewportY + item.height / 2;
        return viewportY < midY ? index : index + 1;
    }

    function updateDropIndicator(gapIndex: int): void {
        const count = sortFilterProxyModel.rowCount();
        if (gapIndex < 0 || gapIndex > count) {
            dropIndicator.visible = false;
            return;
        }

        let lineYInContent;
        if (gapIndex === 0) {
            const first = itemsList.itemAtIndex(0);
            lineYInContent = first ? first.y : 0;
        } else if (gapIndex === count) {
            const last = itemsList.itemAtIndex(count - 1);
            if (!last) {
                dropIndicator.visible = false;
                return;
            }
            lineYInContent = last.y + last.height;
        } else {
            const item = itemsList.itemAtIndex(gapIndex);
            if (!item) {
                dropIndicator.visible = false;
                return;
            }
            lineYInContent = item.y;
        }
        dropIndicator.visible = true;
        dropIndicator.y = lineYInContent;
    }

    function commitReorder(fromIndex: int, gapIndex: int): void {
        if (fromIndex < 0 || gapIndex < 0) return;
        if (gapIndex === fromIndex || gapIndex === fromIndex + 1) return;

        const model = sortFilterProxyModel;
        const ids = [];
        for (let i = 0; i < model.rowCount(); ++i) {
            ids.push(model.index(i, 0).data(Qt.UserRole + 2));
        }
        if (fromIndex >= ids.length || gapIndex > ids.length) return;

        const [moved] = ids.splice(fromIndex, 1);
        const adjustedGap = (fromIndex < gapIndex) ? gapIndex - 1 : gapIndex;
        ids.splice(adjustedGap, 0, moved);
        Plasmoid.setManualOrder(ids);
    }

    component TrayItemDelegate: QQC2.ItemDelegate {
        id: listItem

        required property var applet
        required property var decoration
        required property string displayText
        required property int index
        required property string itemId
        required property string itemType

        width: itemsList.width

        Kirigami.Theme.useAlternateBackgroundColor: true

        highlighted: false
        hoverEnabled: false
        down: false

        readonly property bool isPlasmoid: itemType === "Plasmoid"

        property int dragStartIndex: -1
        property int currentGapIndex: -1

        opacity: dragMouse.pressed ? 0.3 : 1.0
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

        contentItem: FocusScope {
            implicitHeight: childrenRect.height

            onActiveFocusChanged: if (activeFocus) {
                listItem.ListView.view.positionViewAtIndex(listItem.index, ListView.Contain);
            }

            RowLayout {
                width: parent.width
                spacing: Kirigami.Units.smallSpacing

                Item {
                    id: dragHandleArea
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: Kirigami.Units.iconSizes.smallMedium
                    visible: iconsPage.cfg_orderingMode === "custom"

                    Kirigami.Icon {
                        id: dragIcon
                        anchors.centerIn: parent
                        width: Kirigami.Units.iconSizes.small
                        height: Kirigami.Units.iconSizes.small
                        source: "transform-move"
                        opacity: dragMouse.pressed ? 1.0 : 0.6
                    }

                    MouseArea {
                        id: dragMouse
                        anchors.fill: parent
                        visible: iconsPage.cfg_orderingMode === "custom"
                        cursorShape: Qt.OpenHandCursor
                        preventStealing: true

                        onPressed: mouse => {
                            listItem.dragStartIndex = listItem.index;
                            listItem.currentGapIndex = -1;
                        }

                        onPositionChanged: mouse => {
                            if (!pressed) return;

                            const viewportPos = dragMouse.mapToItem(itemsList, mouse.x, mouse.y);
                            listItem.currentGapIndex = iconsPage.computeGapIndex(viewportPos.y);
                            iconsPage.updateDropIndicator(listItem.currentGapIndex);

                            // auto-scroll when dragging item reaches viewport edges
                            scrollTimer.running = (itemsList.contentHeight > itemsList.height)
                                && ((viewportPos.y <= 0 && !itemsList.atYBeginning)
                                    || (viewportPos.y >= itemsList.height - 1 && !itemsList.atYEnd));
                        }

                        onReleased: drop()
                        onCanceled: drop()

                        function drop() {
                            scrollTimer.running = false;
                            dropIndicator.visible = false;
                            if (listItem.currentGapIndex >= 0) {
                                iconsPage.commitReorder(listItem.dragStartIndex, listItem.currentGapIndex);
                            }
                            listItem.currentGapIndex = -1;
                        }

                        Timer {
                            id: scrollTimer
                            interval: 50
                            repeat: true
                            onTriggered: {
                                const viewportPos = dragMouse.mapToItem(itemsList, width / 2, height / 2);
                                if (viewportPos.y < Kirigami.Units.gridUnit * 2) {
                                    itemsList.contentY -= Kirigami.Units.gridUnit;
                                    if (itemsList.atYBeginning) {
                                        itemsList.positionViewAtBeginning();
                                        stop();
                                    }
                                } else {
                                    itemsList.contentY += Kirigami.Units.gridUnit;
                                    if (itemsList.atYEnd) {
                                        itemsList.positionViewAtEnd();
                                        stop();
                                    }
                                }
                                listItem.currentGapIndex = iconsPage.computeGapIndex(viewportPos.y);
                                iconsPage.updateDropIndicator(listItem.currentGapIndex);
                            }
                        }
                    }
                }

                Kirigami.Icon {
                    implicitWidth: itemsList.iconSize
                    implicitHeight: itemsList.iconSize
                    source: listItem.decoration
                    animated: false
                }

                QQC2.Label {
                    id: nameLabel
                    Layout.fillWidth: true
                    maximumLineCount: 1
                    text: listItem.displayText
                    textFormat: Text.PlainText
                    elide: Text.ElideRight

                    QQC2.ToolTip {
                        visible: listItem.hovered && nameLabel.truncated
                        text: nameLabel.text
                    }
                }

                QQC2.ComboBox {
                    id: visibilityComboBox

                    readonly property string currentVisibility: iconsPage.changedVisibility.has(listItem.itemId) ? iconsPage.changedVisibility.get(listItem.itemId).replace("-sni", "") : originalVisibility
                    readonly property string originalVisibility: {
                        if (iconsPage.cfg_showAllItems || iconsPage.cfg_shownItems.indexOf(listItem.itemId) !== -1) {
                            return "shown";
                        } else if (iconsPage.cfg_hiddenItems.indexOf(listItem.itemId) !== -1) {
                            return "hidden";
                        } else if ((listItem.isPlasmoid && iconsPage.cfg_extraItems.indexOf(listItem.itemId) === -1) || (!listItem.isPlasmoid && iconsPage.cfg_disabledStatusNotifiers.indexOf(listItem.itemId) > -1)) {
                            return "disabled";
                        } else {
                            return "auto";
                        }
                    }

                    implicitContentWidthPolicy: QQC2.ComboBox.WidestText

                    enabled: !iconsPage.cfg_showAllItems && listItem.itemId
                    textRole: "text"
                    valueRole: "value"

                    currentIndex: {
                        for (let i = 0; i < model.length; i++) {
                            if (model[i].value === currentVisibility) {
                                return i;
                            }
                        }

                        return 0;
                    }
                    model: iconsPage.comboBoxModel

                    onActivated: index => {
                        if (currentValue !== originalVisibility) {
                            if (currentValue === "disabled" && !listItem.isPlasmoid) {
                                disablingSniMessage.showWithAppName(nameLabel.text);
                            }
                            iconsPage.changedVisibility.set(listItem.itemId, currentValue + (listItem.isPlasmoid ? "" : "-sni"));
                        } else {
                            iconsPage.changedVisibility.delete(listItem.itemId);
                        }
                        iconsPage.changedVisibilityChanged();
                    }
                }

                KQC.KeySequenceItem {
                    id: keySequenceItem
                    Layout.minimumWidth: itemsList.keySequenceColumnWidth
                    Layout.preferredWidth: itemsList.keySequenceColumnWidth

                    // We want to keep the column the same size for all items,
                    // but only when not inputting a new shortcut, as the length
                    // of the shortcut may vary quite a bit while inputting. So
                    // rather than binding to widthChanged, we update the maximum
                    // column width only at specific moments: When the item is
                    // first added, or when we know the shortcut has changed and
                    // no further input happens.
                    function updateColumnWidth() {
                        itemsList.keySequenceColumnWidth = Math.max(implicitWidth, itemsList.keySequenceColumnWidth);
                    }

                    // Delay this one tick to make sure the item has finished
                    // any layout that still needs to be done.
                    Component.onCompleted: Qt.callLater(updateColumnWidth)

                    visible: listItem.isPlasmoid
                    enabled: visibilityComboBox.currentValue !== "disabled"
                    readonly property string originalKeySequence: listItem.applet ? listItem.applet.plasmoid.globalShortcut : ""
                    keySequence: iconsPage.changedShortcuts.has(listItem.applet?.plasmoid) ? iconsPage.changedShortcuts.get(listItem.applet?.plasmoid) : originalKeySequence

                    onCaptureFinished: {
                        if (listItem.applet) {
                            if (keySequence !== listItem.applet.plasmoid.globalShortcut) {
                                iconsPage.changedShortcuts.set(listItem.applet.plasmoid, keySequence.toString());
                            } else {
                                iconsPage.changedShortcuts.delete(listItem.applet.plasmoid);
                            }
                            iconsPage.changedShortcutsChanged();

                            updateColumnWidth()
                        }
                    }
                }
                // Placeholder for when KeySequenceItem is not visible
                Item {
                    Layout.minimumWidth: itemsList.keySequenceColumnWidth
                    Layout.maximumWidth: itemsList.keySequenceColumnWidth
                    visible: !keySequenceItem.visible
                }

                QQC2.Button {
                    readonly property QtObject configureAction: (listItem.applet && listItem.applet.plasmoid.internalAction("configure")) || null

                    Accessible.name: configureAction ? configureAction.text : ""
                    icon.name: "configure"
                    enabled: configureAction && configureAction.visible && configureAction.enabled
                    // Still reserve layout space, so not setting visible to false
                    opacity: enabled ? 1 : 0
                    onClicked: configureAction.trigger()

                    QQC2.ToolTip {
                        // Strip out ampersands right before non-whitespace characters, i.e.
                        // those used to determine the alt key shortcut
                        text: parent.Accessible.name.replace(/&(?=\S)/g, "")
                    }
                }
            }
        }
    }
}
