/*
 * OrangePi-3B (RK3566) Power HAL
 */

#pragma once

#include <aidl/android/hardware/power/BnPower.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <vector>

#include "PowerHintSession.h"

namespace aidl::android::hardware::power::impl::_6xyun {

class Power : public BnPower {
  public:
    Power();

    ndk::ScopedAStatus setMode(Mode type, bool enabled) override;
    ndk::ScopedAStatus isModeSupported(Mode type, bool* _aidl_return) override;
    ndk::ScopedAStatus setBoost(Boost type, int32_t durationMs) override;
    ndk::ScopedAStatus isBoostSupported(Boost type, bool* _aidl_return) override;
    ndk::ScopedAStatus createHintSession(int32_t tgid, int32_t uid,
                                         const std::vector<int32_t>& threadIds,
                                         int64_t durationNanos,
                                         std::shared_ptr<IPowerHintSession>* _aidl_return) override;
    ndk::ScopedAStatus createHintSessionWithConfig(
            int32_t tgid, int32_t uid, const std::vector<int32_t>& threadIds, int64_t durationNanos,
            SessionTag tag, SessionConfig* config,
            std::shared_ptr<IPowerHintSession>* _aidl_return) override;
    ndk::ScopedAStatus getHintSessionPreferredRate(int64_t* outNanoseconds) override;
    ndk::ScopedAStatus getSessionChannel(int32_t tgid, int32_t uid,
                                         ChannelConfig* _aidl_return) override;
    ndk::ScopedAStatus closeSessionChannel(int32_t tgid, int32_t uid) override;
    ndk::ScopedAStatus getSupportInfo(SupportInfo* _aidl_return) override;
    ndk::ScopedAStatus getCpuHeadroom(const CpuHeadroomParams& params,
                                      CpuHeadroomResult* _aidl_return) override;
    ndk::ScopedAStatus getGpuHeadroom(const GpuHeadroomParams& params,
                                      GpuHeadroomResult* _aidl_return) override;
    ndk::ScopedAStatus sendCompositionData(const std::vector<CompositionData>& in_data) override;
    ndk::ScopedAStatus sendCompositionUpdate(const CompositionUpdate& in_update) override;

  private:
    void ApplyCpuLimitsLocked();
    void ApplyCpuBoostLocked(uint32_t util);
    int64_t ResolveCpuMaxFreq(double ratio) const;

    std::mutex mMutex;
    bool mLowPower = false;
    bool mSustainedPerformance = false;
    bool mFixedPerformance = false;
    int64_t mCpuMaxFreq = 0;
    int64_t mLowPowerMaxFreq = 0;
    int64_t mSustainedMaxFreq = 0;
    std::vector<int64_t> mCpuFreqTable;

    std::atomic<uint64_t> mBoostGeneration{0};
    std::vector<std::weak_ptr<PowerHintSession>> mHintSessions;
};

}  // namespace aidl::android::hardware::power::impl::_6xyun
