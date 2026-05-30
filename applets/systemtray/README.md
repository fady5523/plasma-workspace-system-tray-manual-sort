# System Tray Manual Sorting — Patch Architecture

## Overview

The stock KDE Plasma system tray sorts icons by category priority (`ApplicationStatus > Communications > SystemServices > Hardware > UnknownCategory`) with `org.kde.plasma.notifications` pinned to the arrow-end. This patch overlays a **custom manual ordering** mode that replaces the category-based sort with an explicit positional ID list, controlled by a `QSortFilterProxyModel` switching strategy.

---

## Configuration Layer — `main.xml`

Three kcfg entries under `[General]`:

| Entry | Type | Default | Role |
|---|---|---|---|
| `manualOrder` | `StringList` | `[]` | Positional encoding: `["id_A", "id_C", "id_B"]` — lower index = closer to arrow in LTR |
| `orderingMode` | `String` | `"direction"` | `"direction"` = default category sort; `"custom"` = `ManualOrder` enum path |
| `respectDirection` | `Bool` | `false` | `true` = Direction combo is respected (LayoutMirroring drives visual order); `false` = Windows-style, user order always maps LTR left-to-right regardless of panel orientation |

`KConfigLoader` auto-generates a `Settings` base class. `SystemTraySettings` wraps it:

```cpp
// systemtraysettings.cpp
const QStringList SystemTraySettings::manualOrder() const {
    return config->property(MANUAL_ORDER_KEY).toStringList();
}
void SystemTraySettings::setManualOrder(const QStringList &order) {
    writeConfigValue(MANUAL_ORDER_KEY, order);
}
```

`writeConfigValue()` uses `KConfigSkeletonItem::setProperty()` → `config->save()` → `config->read()`, guarded by `updatingConfigValue` to suppress re-entrant `loadConfig()` calls. On every `writeConfigValue` the signal `configurationChanged()` fires, which propagates to both `SortedSystemTrayModel` instances.

---

## Proxy Model Architecture — `sortedsystemtraymodel.h/.cpp`

### Three-way Sorting Strategy

```
SortedSystemTrayModel (QSortFilterProxyModel)
├── SortingType::ConfigurationPage   → lessThanConfigurationPage()
│   Alphabetical category sort, used when "Custom Order" is OFF on the config page.
│
├── SortingType::SystemTray          → lessThanSystemTray()
│   Ordered category sort (priority order), notifications always anchored at arrow.
│   Used when "Custom Order" is OFF in the panel.
│
└── SortingType::ManualOrder         → lessThanManualOrder()
    Positional sort from manualOrder string list.
    No categories, no notifications pinning.
```

### Switching Mechanism

`setSortingType()` merely swaps an enum and calls `invalidate()`:

```cpp
void SortedSystemTrayModel::setSortingType(SortingType sorting) {
    if (m_sorting != sorting) {
        m_sorting = sorting;
        invalidate();  // re-runs lessThan() on every row pair
    }
}
```

The dispatcher in `lessThan()`:

```cpp
bool SortedSystemTrayModel::lessThan(const QModelIndex &left, const QModelIndex &right) const {
    switch (m_sorting) {
    case SortingType::ConfigurationPage: return lessThanConfigurationPage(left, right);
    case SortingType::SystemTray:        return lessThanSystemTray(left, right);
    case SortingType::ManualOrder:       return lessThanManualOrder(left, right);
    }
    return QSortFilterProxyModel::lessThan(left, right);
}
```

### `lessThanManualOrder()` — The Core Comparator

```cpp
bool SortedSystemTrayModel::lessThanManualOrder(
    const QModelIndex &left, const QModelIndex &right) const
{
    const QString leftId = left.data(static_cast<int>(BaseModel::BaseRole::ItemId)).toString();
    const QString rightId = right.data(static_cast<int>(BaseModel::BaseRole::ItemId)).toString();

    const QStringList order = m_settings->manualOrder();
    const int leftIdx = order.indexOf(leftId);
    const int rightIdx = order.indexOf(rightId);

    if (leftIdx == -1 && rightIdx == -1) return false;  // stable: preserve insertion order

    const bool respectDir = m_settings && m_settings->respectDirection();

    if (respectDir) {
        // Ascending position sort.
        // Visual direction is handled by QQuickGridView's layoutDirection property,
        // which is set in QML via LayoutMirroring.
        if (leftIdx == -1) return true;   // unknown items sort first (arrow-ward)
        if (rightIdx == -1) return false;
        return leftIdx < rightIdx;
    } else {
        // Direction-independent sort (Windows-style).
        // QQuickGridView overrides layoutDirection() with its own m_layoutDirection
        // member — LayoutMirroring in QML DOES NOT affect GridView cell order.
        //
        // LTR panel w/ arrow on right:
        //   [col0](arrow-ward) ... [colN](arrow-distal) [▲]
        //
        // RTL panel w/ arrow on left:
        //   [▲] [col0](arrow-ward) ... [colN](arrow-distal)
        //
        // Cell 0 is always arrow-ward in GridView coordinates.
        // When reverseIconOrder=true (RTL), we must reverse the sort so that
        // manualOrder[0] ends up farthest from the arrow visually.
        const bool reversed = m_settings && m_settings->reverseIconOrder();
        if (leftIdx == -1) return !reversed;
        if (rightIdx == -1) return reversed;
        return reversed ? leftIdx > rightIdx : leftIdx < rightIdx;
    }
}
```

**Key insight about GridView:** `QQuickGridView` has its own `layoutDirection` property that it reads in `QQuickGridViewPrivate::updateLayout()`. This is NOT affected by `LayoutMirroring.enabled` — the GridView explicitly overrides `layoutDirection()` with `m_layoutDirection`. Mirroring only affects the visual arrow indicator and RTL-aware delegates, not the cell positioning algorithm. This is why we must manually reverse the sort when `reverseIconOrder` is true under `respectDirection=false`.

---

## QML ⇄ C++ Bridge — `Qt::UserRole + 2`

### Role Registration

In `BaseModel` (the root of the model hierarchy):

```
BaseModel::BaseRole::ItemId == Qt::UserRole + 2
```

This is the canonical role for reading a tray entry's unique identifier. It is used in three places:

1. **`lessThanManualOrder()`** — reads IDs to look up positions in `manualOrder`
2. **`ensureManualOrderContainsAllItems()`** — iterates the source model to discover unlisted IDs
3. **`commitReorder()` in QML** — reads IDs from `sortFilterProxyModel` to build the reordered list

### Q_INVOKABLE Bridge

```cpp
// systemtray.h
Q_INVOKABLE void setManualOrder(const QStringList &order);
Q_INVOKABLE QStringList manualOrder() const;
// systemtray.cpp
void SystemTray::setManualOrder(const QStringList &order) {
    if (m_settings) m_settings->setManualOrder(order);
}
```

In QML, accessed as:

```qml
Plasmoid.setManualOrder(["id3", "id1", "id2"]);
Plasmoid.manualOrder();  // → QStringList
```

### New-Item Bootstrapping

When `orderingMode == "custom"` and an item not in `manualOrder` appears, `ensureManualOrderContainsAllItems()` prepends it:

```cpp
void SystemTray::ensureManualOrderContainsAllItems() {
    auto *model = systemTrayModel();
    QStringList order = m_settings->manualOrder();
    bool changed = false;
    for (int i = 0; i < model->rowCount(); ++i) {
        QString id = model->index(i, 0)
            .data(static_cast<int>(BaseModel::BaseRole::ItemId)).toString();
        if (!order.contains(id)) {
            order.prepend(id);  // new items appear first (arrow-ward)
            changed = true;
        }
    }
    if (changed) m_settings->setManualOrder(order);
}
```

This runs on model creation and on every `configurationChanged` while in custom mode.

---

## Frontend Drag-and-Drop — `ConfigGeneral.qml`

### Design Principles

1. **No floating delegate** — the entry stays in its ListView wrapper during drag. Only the drop indicator line moves. The dimmed entry signals the drag state via `opacity: 0.3`.
2. **No reparenting** — avoids model invalidation stealing the mouse grab.
3. **Line clips between entries** — uses `Kirigami.Theme.highlightColor` for KDE accent color.

### Gap Index Computation

```
Gap 0:   line at item[0].y                   (before first item)
Gap i:   line at item[i].y                    (between item[i-1] and item[i])
Gap N:   line at item[N-1].y + item[N-1].h    (after last item)
```

```qml
function computeGapIndex(viewportY: real): int {
    const index = itemsList.indexAt(1, viewportY);
    if (index < 0) return viewportY < 0 ? 0 : count;
    const item = itemsList.itemAtIndex(index);
    const itemViewportY = item.y - itemsList.contentY;
    const midY = itemViewportY + item.height / 2;
    return viewportY < midY ? index : index + 1;
}
```

### Drop Indicator Positioning

The indicator is a `Rectangle` parented at runtime to `itemsList.contentItem`:

```qml
Rectangle {
    id: dropIndicator
    height: 2
    color: Kirigami.Theme.highlightColor
    opacity: 0.8
    z: 999
    Component.onCompleted: parent = itemsList.contentItem
}
```

`updateDropIndicator` sets `dropIndicator.y = lineYInContent` — both `itemAtIndex(i).y` and `dropIndicator.y` are in `contentItem` coordinate space, so no offset correction is needed.

### Commit Operation

```qml
function commitReorder(fromIndex: int, gapIndex: int): void {
    const model = sortFilterProxyModel;
    const ids = [];
    for (let i = 0; i < model.rowCount(); ++i)
        ids.push(model.index(i, 0).data(Qt.UserRole + 2));
    const [moved] = ids.splice(fromIndex, 1);
    const adjustedGap = (fromIndex < gapIndex) ? gapIndex - 1 : gapIndex;
    ids.splice(adjustedGap, 0, moved);
    Plasmoid.setManualOrder(ids);
}
```

The `adjustedGap` correction: after `splice(fromIndex, 1)`, all entries above `fromIndex` shift left by one position. If the target gap was above the removed index, we subtract 1 to account for the shift. The result is that the dropped entry lands **above** the drop line (the line marks the top edge of the entry at `gapIndex`).

### Auto-Scroll

A 50ms `Timer` scrolls the ListView when the drag handle enters the top/bottom 2 gridUnits of the viewport. The gap index is recomputed every tick.

---

## Known Issues & Limitations

### Mid-Drag Index Shifting

If an application closes (or a tray entry is removed) while the user is mid-drag, the underlying `sortFilterProxyModel` row count changes. The `dragStartIndex` captured in `onPressed` becomes stale — it refers to a row that may now contain a different entry. When `commitReorder` executes the splice, it operates on the wrong element, moving an unintended applet and corrupting the sort order.

### Duplicate App IDs

Running multiple instances of the same StatusNotifier application produces identical `ItemId` strings. When two or more rows share the same ID, `QStringList::indexOf()` returns the first match for both entries, permanently gluing them together — they always occupy adjacent positions and cannot be separated by drag-and-drop.

### Visual Clipping on Entry Mutation

Opening a new application while the config page is open (and an entry is being dragged, or simply while the model is populated) causes visual clipping and misaligned delegate positions. The ListView's displaced transitions may not fully resolve, leaving items in incorrect visual positions until the page is closed and reopened.

### Visual Glitches in Indicator Line

When dragging an applet, the visual indicator line that shows the insertion point gets desynced while scrolling. It currently drifts further away from the cursor the further you scroll, failing to track the scroll position correctly.

