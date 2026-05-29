This repo is an experimental PoC fork of [plasma-workspace](https://github.com/kde/plasma-workspace) from KDE that aims to add manual ordering of system-tray icons

full details [here](./applets/systemtray/README.md)

> **Note:** This implementation was Vibe Coded and only tested on Desktop and will not be updated further.

## Installation Guide

### 1. Clone the repository

```
git clone https://github.com/fady5523/plasma-workspace-system-tray-manual-sort.git && cd plasma-workspace-system-tray-manual-sort
```
 
### 2. Install the dependencies 

**For Arch based distributions:**

```
sudo pacman -S --needed \
  base-devel \
  cmake \
  extra-cmake-modules \
  qt6-base \
  qt6-declarative \
  qt6-svg \
  kconfig \
  kcoreaddons \
  ki18n \
  kiconthemes \
  kitemmodels \
  kio \
  kjobwidgets \
  kservice \
  kwindowsystem \
  kxmlgui \
  kdbusaddons \
  karchive \
  kstatusnotifieritem \
  knotifications \
  krunner \
  kglobalaccel \
  libplasma \
  plasma-workspace \
  plasma-wayland-protocols \
  libdbusmenu-lxqt \
  wayland \
  wayland-protocols
```
 
**For Debian based distributions:**

```
sudo apt build-dep plasma-workspace && sudo apt install cmake extra-cmake-modules \
  qt6-base-dev qt6-declarative-dev \
  qt6-svg-dev libkf6config-dev \
  libkf6coreaddons-dev libkf6i18n-dev \
  libkf6iconthemes-dev \
  libkf6itemmodels-dev \
  libkf6kio-dev \
  libkf6jobwidgets-dev \
  libkf6service-dev \
  libkf6windowsystem-dev \
  libkf6xmlgui-dev \
  libkf6dbusaddons-dev \
  libkf6archive-dev \
  libkf6statusnotifieritem-dev \
  libkf6notifications-dev \
  libkf6runner-dev \
  libkf6globalaccel-dev \
  plasma-workspace-dev \
  libplasma-dev \
  libdbusmenu-lxqt-dev \
  libwayland-dev \
  wayland-protocols
``` 

**For Red Hat based distributions:** 

```
sudo dnf builddep plasma-workspace && sudo dnf install cmake \
  extra-cmake-modules \
  qt6-qtbase-devel \
  qt6-qtdeclarative-devel \
  qt6-qtsvg-devel \
  kf6-kconfig-devel \
  kf6-kcoreaddons-devel \
  kf6-ki18n-devel \
  kf6-kiconthemes-devel \
  kf6-kitemmodels-devel \
  kf6-kio-devel \
  kf6-kjobwidgets-devel \
  kf6-kservice-devel \
  kf6-kwindowsystem-devel \
  kf6-kxmlgui-devel \
  kf6-kdbusaddons-devel \
  kf6-karchive-devel \
  kf6-kstatusnotifieritem-devel \
  kf6-knotifications-devel \
  kf6-krunner-devel \
  kf6-kglobalaccel-devel \
  plasma-workspace-devel \
  libplasma-devel \
  libdbusmenu-lxqt-devel \
  wayland-devel \
  wayland-protocols-devel
``` 

### 3. build (I recommend only building the system tray)

```
cmake -B build -DCMAKE_INSTALL_PREFIX=/tmp/plasma-staging -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF

cmake --build build --target org.kde.plasma.systemtray
```
### 4. Replace the system tray files 

**For Arch:** 

```
sudo cp build/bin/plasma/applets/org.kde.plasma.systemtray.so /usr/lib/qt6/plugins/plasma/applets/
```

**For Debian:** 

```
sudo cp build/bin/plasma/applets/org.kde.plasma.systemtray.so /usr/lib/x86_64-linux-gnu/qt6/plugins/plasma/applets/
```

**For Red Hat:** 

```
sudo cp build/bin/plasma/applets/org.kde.plasma.systemtray.so /usr/lib64/qt6/plugins/plasma/applets/
```

### 5. Restart the plasmashell

```
systemctl --user restart plasma-plasmashell
```

## Plasma Workspace

Plasma Workspace is used as the base for Plasma Desktop, Mobile, and Bigscreen.
It contains shared KCMs, applets as well as multiple libraries.

### TaskManager Library

The Task Manager provides various QAbstractListModel-based model for listing
Windows (TaskManager::AbstractWindowTasksModel), Startup tasks (TaskManager::StartupTasksModel) and Launcher
Job (TaskManager::LauncherTasksModel).

### Workspace Library

libkworkspace provides functions to allow you to interact with the
%KDE session manager (SessionManagement).

### Notification Manager Library

libnotificationmanager is responsible for listing notifications, closing them
and interacting with them in Plasma. This class provides a %Qt model for jobs:
NotificationManager::JobsModel. As well as a %Qt model for notifications and
jobs: NotificationManager::Notifications.
