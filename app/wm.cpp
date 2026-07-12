#include <QtGlobal>
#include <QDir>

#include "utils.h"

#include "SDL_compat.h"

bool WMUtils::isRunningWayland()
{
    return false;
}

bool WMUtils::isRunningDesktopEnvironment()
{
    bool value;
    if (Utils::getEnvironmentVariableOverride("HAS_DESKTOP_ENVIRONMENT", &value)) {
        return value;
    }

    // macOS is always running a desktop environment
    return true;
}

bool WMUtils::isGpuSlow()
{
    bool ret;

    if (!Utils::getEnvironmentVariableOverride("GL_IS_SLOW", &ret)) {
#if defined(GL_IS_SLOW)
        ret = true;
#else
        ret = false;
#endif
    }

    return ret;
}
