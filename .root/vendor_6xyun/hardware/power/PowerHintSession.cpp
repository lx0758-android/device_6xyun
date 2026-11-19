/*
 * OrangePi-3B (RK3566) Power HAL —— ADPF hint session
 *
 * 这里用 uclamp 实现最小可用的 ADPF：
 *   - target duration 越短，说明工作越紧，给线程越高的 util 下限；
 *   - reportActual 超过 target 时上调，低于 target 时缓慢下调；
 *   - 只操作会话给出的线程，不改变全局调度策略。
 */

#include "PowerHintSession.h"

#include <android-base/logging.h>

#include "Utils.h"

#include <algorithm>

namespace aidl::android::hardware::power::impl::_6xyun {

namespace {
constexpr int32_t kUtilMax = 1024;
// 以 60Hz 的 16.67ms 为基准：目标 16.67ms 时给约 50% 的 util 下限。
constexpr int64_t kReferenceWorkNanos = 8333333;
}  // namespace

PowerHintSession::PowerHintSession(std::vector<int32_t> threadIds, int64_t durationNanos)
    : mThreadIds(std::move(threadIds)), mTargetDurationNanos(durationNanos) {
    if (mTargetDurationNanos <= 0) {
        mTargetDurationNanos = 16666666;
    }
    std::lock_guard<std::mutex> lock(mLock);
    RecomputeLocked();
    ApplyLocked();
}

PowerHintSession::~PowerHintSession() {
    std::lock_guard<std::mutex> lock(mLock);
    mUtil = 0;
    mClosed = true;
    ApplyLocked();
}

void PowerHintSession::RecomputeLocked() {
    if (mTargetDurationNanos <= 0) {
        mUtil = 0;
        return;
    }
    // util = 1024 * reference / target，夹在 [0, 1024]。
    const int64_t util = kUtilMax * kReferenceWorkNanos / mTargetDurationNanos;
    mUtil = static_cast<int32_t>(std::clamp<int64_t>(util, 0, kUtilMax));
}

void PowerHintSession::AdjustLocked(int32_t delta) {
    mUtil = std::clamp<int32_t>(mUtil + delta, 0, kUtilMax);
}

void PowerHintSession::ApplyLocked() {
    const uint32_t utilMin =
            (mClosed || mPaused || mPowerEfficiency) ? 0 : static_cast<uint32_t>(mUtil);
    for (int32_t tid : mThreadIds) {
        if (tid <= 0) {
            continue;
        }
        if (!SetTaskUclamp(tid, utilMin, kUtilMax)) {
            // 线程可能已经退出，属于正常情况，不打错误日志。
            LOG(VERBOSE) << "sched_setattr failed for tid " << tid;
        }
    }
}

ndk::ScopedAStatus PowerHintSession::updateTargetWorkDuration(int64_t targetDurationNanos) {
    if (targetDurationNanos <= 0) {
        return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
    }
    std::lock_guard<std::mutex> lock(mLock);
    mTargetDurationNanos = targetDurationNanos;
    RecomputeLocked();
    ApplyLocked();
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus PowerHintSession::reportActualWorkDuration(
        const std::vector<WorkDuration>& durations) {
    if (durations.empty()) {
        return ndk::ScopedAStatus::ok();
    }

    int64_t total = 0;
    for (const auto& duration : durations) {
        total += duration.durationNanos;
    }
    const int64_t average = total / static_cast<int64_t>(durations.size());

    std::lock_guard<std::mutex> lock(mLock);
    if (average > mTargetDurationNanos) {
        AdjustLocked(64);
    } else {
        AdjustLocked(-32);
    }
    ApplyLocked();
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus PowerHintSession::pause() {
    std::lock_guard<std::mutex> lock(mLock);
    mPaused = true;
    ApplyLocked();
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus PowerHintSession::resume() {
    std::lock_guard<std::mutex> lock(mLock);
    mPaused = false;
    ApplyLocked();
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus PowerHintSession::close() {
    std::lock_guard<std::mutex> lock(mLock);
    mClosed = true;
    mUtil = 0;
    ApplyLocked();
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus PowerHintSession::sendHint(SessionHint hint) {
    std::lock_guard<std::mutex> lock(mLock);
    switch (hint) {
        case SessionHint::CPU_LOAD_UP:
            AdjustLocked(128);
            break;
        case SessionHint::CPU_LOAD_DOWN:
            AdjustLocked(-128);
            break;
        case SessionHint::CPU_LOAD_RESET:
            RecomputeLocked();
            break;
        case SessionHint::CPU_LOAD_SPIKE:
            AdjustLocked(256);
            break;
        case SessionHint::CPU_LOAD_RESUME:
            mPaused = false;
            break;
        default:
            // GPU 相关 hint 暂不参与 CPU uclamp。
            return ndk::ScopedAStatus::ok();
    }
    ApplyLocked();
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus PowerHintSession::setThreads(const std::vector<int32_t>& threadIds) {
    if (threadIds.empty()) {
        return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
    }
    std::lock_guard<std::mutex> lock(mLock);
    mThreadIds = threadIds;
    ApplyLocked();
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus PowerHintSession::setMode(SessionMode mode, bool enabled) {
    std::lock_guard<std::mutex> lock(mLock);
    switch (mode) {
        case SessionMode::POWER_EFFICIENCY:
            mPowerEfficiency = enabled;
            break;
        case SessionMode::GRAPHICS_PIPELINE:
            // 图形管线本身已经通过 uclamp 提升，无需额外处理。
            break;
        default:
            return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
    }
    ApplyLocked();
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus PowerHintSession::getSessionConfig(SessionConfig* _aidl_return) {
    if (_aidl_return == nullptr) {
        return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
    }
    _aidl_return->id = 1;
    return ndk::ScopedAStatus::ok();
}

}  // namespace aidl::android::hardware::power::impl::_6xyun
