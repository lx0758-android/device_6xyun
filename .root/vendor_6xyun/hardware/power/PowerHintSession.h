/*
 * OrangePi-3B (RK3566) Power HAL —— ADPF hint session
 */

#pragma once

#include <aidl/android/hardware/power/BnPowerHintSession.h>

#include <mutex>
#include <vector>

namespace aidl::android::hardware::power::impl::_6xyun {

class PowerHintSession : public BnPowerHintSession {
  public:
    PowerHintSession(std::vector<int32_t> threadIds, int64_t durationNanos);
    ~PowerHintSession() override;

    ndk::ScopedAStatus updateTargetWorkDuration(int64_t targetDurationNanos) override;
    ndk::ScopedAStatus reportActualWorkDuration(
            const std::vector<WorkDuration>& durations) override;
    ndk::ScopedAStatus pause() override;
    ndk::ScopedAStatus resume() override;
    ndk::ScopedAStatus close() override;
    ndk::ScopedAStatus sendHint(SessionHint hint) override;
    ndk::ScopedAStatus setThreads(const std::vector<int32_t>& threadIds) override;
    ndk::ScopedAStatus setMode(SessionMode mode, bool enabled) override;
    ndk::ScopedAStatus getSessionConfig(SessionConfig* _aidl_return) override;

  private:
    void ApplyLocked();
    void RecomputeLocked();
    void AdjustLocked(int32_t delta);

    std::mutex mLock;
    std::vector<int32_t> mThreadIds;
    int64_t mTargetDurationNanos;
    int32_t mUtil = 0;
    bool mPaused = false;
    bool mClosed = false;
    bool mPowerEfficiency = false;
};

}  // namespace aidl::android::hardware::power::impl::_6xyun
