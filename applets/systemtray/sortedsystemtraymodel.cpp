/*
    SPDX-FileCopyrightText: 2019 Konrad Materka <materka@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "sortedsystemtraymodel.h"
#include "debug.h"
#include "systemtraymodel.h"
#include "systemtraysettings.h"

#include <QList>
#include <climits>

static const QList<QString> s_categoryOrder = {
    QStringLiteral("UnknownCategory"),
    QStringLiteral("ApplicationStatus"),
    QStringLiteral("Communications"),
    QStringLiteral("SystemServices"),
    QStringLiteral("Hardware"),
};

SortedSystemTrayModel::SortedSystemTrayModel(SortingType sorting, SystemTraySettings *settings, QObject *parent)
    : QSortFilterProxyModel(parent)
    , m_sorting(sorting)
    , m_settings(settings)
{
    setSortLocaleAware(true);
    sort(0);
}

void SortedSystemTrayModel::setSortingType(SortingType sorting)
{
    if (m_sorting != sorting) {
        m_sorting = sorting;
        invalidate();
    }
}

bool SortedSystemTrayModel::lessThan(const QModelIndex &left, const QModelIndex &right) const
{
    switch (m_sorting) {
    case SortedSystemTrayModel::SortingType::ConfigurationPage:
        return lessThanConfigurationPage(left, right);
    case SortedSystemTrayModel::SortingType::SystemTray:
        return lessThanSystemTray(left, right);
    case SortedSystemTrayModel::SortingType::ManualOrder:
        return lessThanManualOrder(left, right);
    }

    return QSortFilterProxyModel::lessThan(left, right);
}

bool SortedSystemTrayModel::lessThanConfigurationPage(const QModelIndex &left, const QModelIndex &right) const
{
    const int categoriesComparison = compareCategoriesAlphabetically(left, right);
    if (categoriesComparison == 0) {
        return QSortFilterProxyModel::lessThan(left, right);
    } else {
        return categoriesComparison < 0;
    }
}

bool SortedSystemTrayModel::lessThanSystemTray(const QModelIndex &left, const QModelIndex &right) const
{
    QVariant itemIdLeft = left.data(static_cast<int>(BaseModel::BaseRole::ItemId));
    QVariant itemIdRight = right.data(static_cast<int>(BaseModel::BaseRole::ItemId));
    if (itemIdRight.toString() == QLatin1String("org.kde.plasma.notifications")) {
        // return false when at least right is "org.kde.plasma.notifications"
        return false;
    } else if (itemIdLeft.toString() == QLatin1String("org.kde.plasma.notifications")) {
        // return true when only left is "org.kde.plasma.notifications"
        return true;
    }

    const int categoriesComparison = compareCategoriesOrderly(left, right);
    if (categoriesComparison == 0) {
        return QSortFilterProxyModel::lessThan(left, right);
    } else {
        return categoriesComparison < 0;
    }
}

int SortedSystemTrayModel::compareCategoriesAlphabetically(const QModelIndex &left, const QModelIndex &right) const
{
    QVariant leftData = left.data(static_cast<int>(BaseModel::BaseRole::Category));
    QString leftCategory = leftData.isNull() ? QStringLiteral("UnknownCategory") : leftData.toString();

    QVariant rightData = right.data(static_cast<int>(BaseModel::BaseRole::Category));
    QString rightCategory = rightData.isNull() ? QStringLiteral("UnknownCategory") : rightData.toString();

    return QString::localeAwareCompare(leftCategory, rightCategory);
}

int SortedSystemTrayModel::compareCategoriesOrderly(const QModelIndex &left, const QModelIndex &right) const
{
    QVariant leftData = left.data(static_cast<int>(BaseModel::BaseRole::Category));
    QString leftCategory = leftData.isNull() ? QStringLiteral("UnknownCategory") : leftData.toString();

    QVariant rightData = right.data(static_cast<int>(BaseModel::BaseRole::Category));
    QString rightCategory = rightData.isNull() ? QStringLiteral("UnknownCategory") : rightData.toString();

    int leftIndex = s_categoryOrder.indexOf(leftCategory);
    if (leftIndex == -1) {
        leftIndex = s_categoryOrder.indexOf(QStringLiteral("UnknownCategory"));
    }

    int rightIndex = s_categoryOrder.indexOf(rightCategory);
    if (rightIndex == -1) {
        rightIndex = s_categoryOrder.indexOf(QStringLiteral("UnknownCategory"));
    }

    return leftIndex - rightIndex;
}

bool SortedSystemTrayModel::lessThanManualOrder(const QModelIndex &left, const QModelIndex &right) const
{
    const QString leftId = left.data(static_cast<int>(BaseModel::BaseRole::ItemId)).toString();
    const QString rightId = right.data(static_cast<int>(BaseModel::BaseRole::ItemId)).toString();

    const QStringList order = m_settings ? m_settings->manualOrder() : QStringList();
    const int leftIdx = order.indexOf(leftId);
    const int rightIdx = order.indexOf(rightId);

    if (leftIdx == -1 && rightIdx == -1) {
        return false;
    }

    const bool respectDir = m_settings && m_settings->respectDirection();

    if (respectDir) {
        // Ascending sort, direction handled by LayoutMirroring in QML.
        // Unknown items sort first (farthest from arrow for LTR).
        if (leftIdx == -1) {
            return true;
        }
        if (rightIdx == -1) {
            return false;
        }
        return leftIdx < rightIdx;
    } else {
        // Direction-independent: GridView cells are always LTR.
        // LTR: [col0](farthest from arrow) ... [colN][▲]
        // RTL: [▲][col0](closest to arrow) ... [colN](farthest from arrow)
        const bool reversed = m_settings && m_settings->reverseIconOrder();
        if (leftIdx == -1) {
            return !reversed;
        }
        if (rightIdx == -1) {
            return reversed;
        }
        return reversed ? leftIdx > rightIdx : leftIdx < rightIdx;
    }
}

#include "moc_sortedsystemtraymodel.cpp"
