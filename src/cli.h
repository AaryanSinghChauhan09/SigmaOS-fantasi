#pragma once

#include <QStringList>

// The commands that need no window: `fantasi generate`, help and version.
bool isCliCommand(const char *argument);

// Runs one, with the application's arguments; the exit code.
int runCli(const QStringList &arguments);
