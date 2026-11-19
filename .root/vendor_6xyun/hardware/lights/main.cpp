/*
 * OrangePi-3B (RK3566) lights HAL 入口
 */

#include "Lights.h"

#include <android-base/logging.h>
#include <android/binder_manager.h>
#include <android/binder_process.h>

using aidl::android::hardware::light::impl::_6xyun::Lights;

int main() {
    ABinderProcess_setThreadPoolMaxThreadCount(0);

    std::shared_ptr<Lights> lights = ndk::SharedRefBase::make<Lights>();
    const std::string instance = std::string() + Lights::descriptor + "/default";
    const binder_status_t status =
            AServiceManager_addService(lights->asBinder().get(), instance.c_str());
    CHECK_EQ(status, STATUS_OK) << "failed to register " << instance;

    ABinderProcess_joinThreadPool();
    return EXIT_FAILURE;  // 不应到达
}
