/*
 * OrangePi-3B (RK3566) lights HAL
 *
 * 硬件只有一颗绿色 LED（gpio-leds），把它注册为通知灯：
 *   - 有通知时把 trigger 切到 none，再写 brightness；
 *   - 通知清除（颜色为 0）时把 trigger 切回 heartbeat；
 *   - 不支持闪烁与动画，相关请求返回未支持。
 */

#include "Lights.h"

#include <aidl/android/hardware/light/FlashMode.h>
#include <aidl/android/hardware/light/LightType.h>

#include <android-base/logging.h>

#include <cstdio>
#include <string>

namespace aidl::android::hardware::light::impl::_6xyun {

namespace {

constexpr const char* kLedName = "android-status";
constexpr int32_t kNotificationId = 0;

std::string LedPath(const char* leaf) {
    return std::string("/sys/class/leds/") + kLedName + "/" + leaf;
}

bool WriteLed(const char* leaf, const std::string& value) {
    const std::string path = LedPath(leaf);
    FILE* fp = fopen(path.c_str(), "we");
    if (fp == nullptr) {
        PLOG(ERROR) << "failed to open " << path;
        return false;
    }
    const bool ok = fputs(value.c_str(), fp) >= 0;
    fclose(fp);
    if (!ok) {
        PLOG(ERROR) << "failed to write " << path;
    }
    return ok;
}

bool SetTrigger(const char* trigger) {
    return WriteLed("trigger", trigger);
}

// AOSP LightsService 约定的单色灯亮度换算。
int32_t ColorToBrightness(int32_t color) {
    const int32_t r = (color >> 16) & 0xff;
    const int32_t g = (color >> 8) & 0xff;
    const int32_t b = color & 0xff;
    return ((77 * r) + (150 * g) + (29 * b)) >> 8;
}

}  // namespace

ndk::ScopedAStatus Lights::setLightState(int32_t id, const HwLightState& state) {
    if (id != kNotificationId) {
        return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
    }

    // GPIO LED 只有开/关，不支持闪烁。
    if (state.flashMode != FlashMode::NONE) {
        return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
    }

    std::lock_guard<std::mutex> lock(mMutex);

    const int32_t brightness = ColorToBrightness(state.color);
    if (brightness <= 0) {
        if (!SetTrigger("heartbeat")) {
            return ndk::ScopedAStatus::fromServiceSpecificError(1);
        }
        return ndk::ScopedAStatus::ok();
    }

    if (!SetTrigger("none")) {
        return ndk::ScopedAStatus::fromServiceSpecificError(1);
    }
    if (!WriteLed("brightness", "1")) {
        return ndk::ScopedAStatus::fromServiceSpecificError(1);
    }

    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Lights::getLights(std::vector<HwLight>* _aidl_return) {
    if (_aidl_return == nullptr) {
        return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
    }

    HwLight light{};
    light.id = kNotificationId;
    light.ordinal = 0;
    light.type = LightType::NOTIFICATIONS;
    light.minUpdatePeriodMillis = 0;

    _aidl_return->clear();
    _aidl_return->push_back(light);
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Lights::setLightEffects(const std::vector<HwLightEffect>& /* effects */) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

}  // namespace aidl::android::hardware::light::impl::_6xyun
