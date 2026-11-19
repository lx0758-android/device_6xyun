/*
 * OrangePi-3B (RK3566) Health HAL
 */

#pragma once

#include <health-impl/Health.h>

#include <memory>
#include <string_view>

namespace aidl::android::hardware::health::impl::_6xyun {

class HealthImpl : public Health {
  public:
    HealthImpl(std::string_view instance_name,
               std::unique_ptr<struct healthd_config>&& config)
        : Health(instance_name, std::move(config)) {}

  protected:
    void UpdateHealthInfo(HealthInfo* health_info) override;
};

}  // namespace aidl::android::hardware::health::impl::_6xyun
