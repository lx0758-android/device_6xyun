/*
 * OrangePi-3B (RK3566) Power HAL
 *
 * 与 AOSP 的 power-service.example 不同，这里把 hint 真正落到硬件可调项：
 *   - Mode  -> cpufreq policy0 的 governor / max_freq（持续性能、低功耗、固定性能）
 *             上限按内核导出的 OPP 表换算，不在代码里写死某个 SoC 的 kHz
 *   - Boost -> 所有 CPU 的 uclamp.min（短时交互/显示更新）
 *   - HintSession -> 目标线程的 uclamp（ADPF）
 *
 * 说明：系统 suspend 由 PowerManagerService/SystemSuspend 决定，不属于本
 * HAL 的职责；USB 连接期间不掉线依赖内核 dwc3 的唤醒能力。
 */

#include "Power.h"

#include <android-base/logging.h>

#include "Utils.h"

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <thread>

namespace aidl::android::hardware::power::impl::_6xyun {

namespace {

constexpr const char* kCpuPolicy = "/sys/devices/system/cpu/cpufreq/policy0";
// 上限用"比例"表达，而不是写死某个 SoC 的 kHz：
// 内核只导出能力（OPP 表 / cpuinfo_max_freq），"低功耗上限"和"持续性能上限"
// 本身是产品策略，内核没有对应节点。这里在运行时按比例从
// scaling_available_frequencies 向下取最近的合法档位，换 SoC 或调整 OPP 表
// 都不需要改代码。
constexpr double kLowPowerMaxRatio = 0.50;
constexpr double kSustainedMaxRatio = 0.80;
// 读不到 cpuinfo_max_freq 时的最后兜底值（本板 A55 最高档）。
constexpr int64_t kFallbackCpuMaxFreq = 1800000;
constexpr int64_t kDefaultSessionRateNs = 16666666;  // 60Hz

std::vector<int64_t> ParseFreqList(const std::string& text) {
    std::vector<int64_t> freqs;
    const char* p = text.c_str();
    while (*p != '\0') {
        char* end = nullptr;
        const long long value = std::strtoll(p, &end, 10);
        if (end == p) {
            ++p;
            continue;
        }
        if (value > 0) {
            freqs.push_back(value);
        }
        p = end;
    }
    std::sort(freqs.begin(), freqs.end());
    freqs.erase(std::unique(freqs.begin(), freqs.end()), freqs.end());
    return freqs;
}

template <class E>
int64_t BitMask(std::initializer_list<E> values) {
    int64_t mask = 0;
    for (const auto& value : values) {
        mask |= 1LL << static_cast<int64_t>(value);
    }
    return mask;
}

}  // namespace

Power::Power() {
    const std::string maxFreq = ReadFile(std::string(kCpuPolicy) + "/cpuinfo_max_freq");
    if (!maxFreq.empty()) {
        mCpuMaxFreq = std::strtoll(maxFreq.c_str(), nullptr, 10);
    }
    if (mCpuMaxFreq <= 0) {
        mCpuMaxFreq = kFallbackCpuMaxFreq;
    }
    // OPP 表由内核导出；读不到时退回比例计算出来的 kHz，内核在 verify
    // 阶段仍会把它向下对齐到合法档位。
    mCpuFreqTable =
            ParseFreqList(ReadFile(std::string(kCpuPolicy) + "/scaling_available_frequencies"));
    mLowPowerMaxFreq = ResolveCpuMaxFreq(kLowPowerMaxRatio);
    mSustainedMaxFreq = ResolveCpuMaxFreq(kSustainedMaxRatio);
    LOG(INFO) << "cpufreq max=" << mCpuMaxFreq << "kHz, low_power=" << mLowPowerMaxFreq
              << "kHz, sustained=" << mSustainedMaxFreq
              << "kHz, opp_count=" << mCpuFreqTable.size();

    std::lock_guard<std::mutex> lock(mMutex);
    ApplyCpuLimitsLocked();
}

// 把策略比例换算成当前 OPP 表里真实存在的频率：向下取档，保证设置的上限
// 不会高于目标比例。表为空时返回比例值本身。
int64_t Power::ResolveCpuMaxFreq(double ratio) const {
    const int64_t target = static_cast<int64_t>(static_cast<double>(mCpuMaxFreq) * ratio);
    if (mCpuFreqTable.empty()) {
        return target;
    }
    int64_t chosen = mCpuFreqTable.front();
    for (const int64_t freq : mCpuFreqTable) {
        if (freq > target) {
            break;
        }
        chosen = freq;
    }
    return chosen;
}

void Power::ApplyCpuLimitsLocked() {
    std::string governor = "schedutil";
    int64_t maxFreq = mCpuMaxFreq;

    if (mFixedPerformance) {
        governor = "performance";
    } else if (mLowPower) {
        maxFreq = std::min<int64_t>(mLowPowerMaxFreq, mCpuMaxFreq);
    } else if (mSustainedPerformance) {
        maxFreq = std::min<int64_t>(mSustainedMaxFreq, mCpuMaxFreq);
    }

    if (!WriteFile(std::string(kCpuPolicy) + "/scaling_governor", governor)) {
        LOG(WARNING) << "failed to set scaling_governor to " << governor;
    }
    const std::string maxFreqPath = std::string(kCpuPolicy) + "/scaling_max_freq";
    if (!WriteFile(maxFreqPath, std::to_string(maxFreq))) {
        LOG(WARNING) << "failed to set scaling_max_freq to " << maxFreq;
    } else {
        // 读回生效值：内核 verify 会把请求值向下对齐到合法档位。
        LOG(VERBOSE) << "scaling_max_freq=" << ReadFile(maxFreqPath) << "kHz (requested "
                     << maxFreq << "kHz)";
    }
}

void Power::ApplyCpuBoostLocked(uint32_t util) {
    // 每 CPU 的 uclamp.min 是整机粒度最轻的 boost 手段，不改变调度策略。
    for (int cpu = 0; cpu < 4; ++cpu) {
        const std::string path =
                "/sys/devices/system/cpu/cpu" + std::to_string(cpu) + "/uclamp.min";
        WriteFile(path, std::to_string(util));
    }
}

ndk::ScopedAStatus Power::setMode(Mode type, bool enabled) {
    std::lock_guard<std::mutex> lock(mMutex);
    switch (type) {
        case Mode::LOW_POWER:
            mLowPower = enabled;
            break;
        case Mode::SUSTAINED_PERFORMANCE:
            mSustainedPerformance = enabled;
            break;
        case Mode::FIXED_PERFORMANCE:
            mFixedPerformance = enabled;
            break;
        case Mode::INTERACTIVE:
            // 交互态本身不改变持久配置，交互压力由 setBoost 承担。
            return ndk::ScopedAStatus::ok();
        default:
            LOG(VERBOSE) << "unsupported mode " << static_cast<int32_t>(type);
            return ndk::ScopedAStatus::ok();
    }
    ApplyCpuLimitsLocked();
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Power::isModeSupported(Mode type, bool* _aidl_return) {
    if (_aidl_return == nullptr) {
        return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
    }
    switch (type) {
        case Mode::LOW_POWER:
        case Mode::SUSTAINED_PERFORMANCE:
        case Mode::FIXED_PERFORMANCE:
        case Mode::INTERACTIVE:
            *_aidl_return = true;
            break;
        default:
            *_aidl_return = false;
            break;
    }
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Power::setBoost(Boost type, int32_t durationMs) {
    uint32_t util = 0;
    int32_t duration = durationMs;

    switch (type) {
        case Boost::INTERACTION:
            util = 512;
            if (duration <= 0) {
                duration = 1000;
            }
            break;
        case Boost::DISPLAY_UPDATE_IMMINENT:
            util = 256;
            if (duration <= 0) {
                duration = 100;
            }
            break;
        default:
            LOG(VERBOSE) << "unsupported boost " << static_cast<int32_t>(type);
            return ndk::ScopedAStatus::ok();
    }

    std::lock_guard<std::mutex> lock(mMutex);
    ApplyCpuBoostLocked(util);
    const uint64_t generation = ++mBoostGeneration;

    std::thread([this, generation, duration]() {
        std::this_thread::sleep_for(std::chrono::milliseconds(duration));
        std::lock_guard<std::mutex> lock(mMutex);
        if (mBoostGeneration.load() == generation) {
            ApplyCpuBoostLocked(0);
        }
    }).detach();

    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Power::isBoostSupported(Boost type, bool* _aidl_return) {
    if (_aidl_return == nullptr) {
        return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
    }
    switch (type) {
        case Boost::INTERACTION:
        case Boost::DISPLAY_UPDATE_IMMINENT:
            *_aidl_return = true;
            break;
        default:
            *_aidl_return = false;
            break;
    }
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Power::createHintSession(int32_t /*tgid*/, int32_t /*uid*/,
                                            const std::vector<int32_t>& threadIds,
                                            int64_t durationNanos,
                                            std::shared_ptr<IPowerHintSession>* _aidl_return) {
    if (_aidl_return == nullptr || threadIds.empty()) {
        return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
    }

    auto session = ndk::SharedRefBase::make<PowerHintSession>(threadIds, durationNanos);
    {
        std::lock_guard<std::mutex> lock(mMutex);
        // 清理已经关闭的会话
        mHintSessions.erase(
                std::remove_if(mHintSessions.begin(), mHintSessions.end(),
                               [](const std::weak_ptr<PowerHintSession>& item) {
                                   return item.expired();
                               }),
                mHintSessions.end());
        mHintSessions.push_back(session);
    }

    *_aidl_return = session;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Power::createHintSessionWithConfig(
        int32_t tgid, int32_t uid, const std::vector<int32_t>& threadIds, int64_t durationNanos,
        SessionTag /*tag*/, SessionConfig* config,
        std::shared_ptr<IPowerHintSession>* _aidl_return) {
    auto status = createHintSession(tgid, uid, threadIds, durationNanos, _aidl_return);
    if (!status.isOk() || _aidl_return == nullptr || *_aidl_return == nullptr) {
        return status;
    }
    if (config != nullptr) {
        config->id = 1;
    }
    return status;
}

ndk::ScopedAStatus Power::getHintSessionPreferredRate(int64_t* outNanoseconds) {
    if (outNanoseconds == nullptr) {
        return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
    }
    *outNanoseconds = kDefaultSessionRateNs;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Power::getSessionChannel(int32_t /*tgid*/, int32_t /*uid*/,
                                            ChannelConfig* /*_aidl_return*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Power::closeSessionChannel(int32_t /*tgid*/, int32_t /*uid*/) {
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Power::getSupportInfo(SupportInfo* _aidl_return) {
    if (_aidl_return == nullptr) {
        return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
    }

    SupportInfo info{};
    info.usesSessions = true;
    info.modes = BitMask<Mode>({Mode::LOW_POWER, Mode::SUSTAINED_PERFORMANCE,
                                Mode::FIXED_PERFORMANCE, Mode::INTERACTIVE});
    info.boosts = BitMask<Boost>({Boost::INTERACTION, Boost::DISPLAY_UPDATE_IMMINENT});
    info.sessionHints =
            BitMask<SessionHint>({SessionHint::CPU_LOAD_UP, SessionHint::CPU_LOAD_DOWN,
                                  SessionHint::CPU_LOAD_RESET, SessionHint::CPU_LOAD_SPIKE,
                                  SessionHint::CPU_LOAD_RESUME});
    info.sessionModes =
            BitMask<SessionMode>({SessionMode::POWER_EFFICIENCY, SessionMode::GRAPHICS_PIPELINE});
    info.sessionTags = 0;
    *_aidl_return = info;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Power::getCpuHeadroom(const CpuHeadroomParams& /*params*/,
                                         CpuHeadroomResult* /*_aidl_return*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Power::getGpuHeadroom(const GpuHeadroomParams& /*params*/,
                                         GpuHeadroomResult* /*_aidl_return*/) {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Power::sendCompositionData(const std::vector<CompositionData>& /*in_data*/) {
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Power::sendCompositionUpdate(const CompositionUpdate& /*in_update*/) {
    return ndk::ScopedAStatus::ok();
}

}  // namespace aidl::android::hardware::power::impl::_6xyun
