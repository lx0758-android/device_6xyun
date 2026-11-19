/*
 * OrangePi-3B (RK3566) lights HAL
 */

#pragma once

#include <aidl/android/hardware/light/BnLights.h>
#include <aidl/android/hardware/light/HwLight.h>
#include <aidl/android/hardware/light/HwLightEffect.h>
#include <aidl/android/hardware/light/HwLightState.h>

#include <mutex>
#include <vector>

namespace aidl::android::hardware::light::impl::_6xyun {

class Lights : public BnLights {
  public:
    Lights() = default;

    ndk::ScopedAStatus setLightState(int32_t id, const HwLightState& state) override;
    ndk::ScopedAStatus getLights(std::vector<HwLight>* _aidl_return) override;
    ndk::ScopedAStatus setLightEffects(const std::vector<HwLightEffect>& effects) override;

  private:
    std::mutex mMutex;
};

}  // namespace aidl::android::hardware::light::impl::_6xyun
