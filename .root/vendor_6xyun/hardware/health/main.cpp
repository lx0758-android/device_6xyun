/*
 * OrangePi-3B (RK3566) Health HAL 入口
 */

#include "HealthImpl.h"

#include <android-base/logging.h>
#include <health-impl/HalHealthLoop.h>
#include <health/utils.h>

#include <memory>

using aidl::android::hardware::health::HalHealthLoop;
using aidl::android::hardware::health::impl::_6xyun::HealthImpl;

int main() {
    auto config = std::make_unique<healthd_config>();
    ::android::hardware::health::InitHealthdConfig(config.get());

    auto binder = ndk::SharedRefBase::make<HealthImpl>("default", std::move(config));
    auto hal_health_loop = std::make_shared<HalHealthLoop>(binder, binder);
    return hal_health_loop->StartLoop();
}
