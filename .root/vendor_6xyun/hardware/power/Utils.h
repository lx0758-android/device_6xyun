/*
 * OrangePi-3B (RK3566) Power HAL 平台工具
 */

#pragma once

#include <cstdint>
#include <cstdio>
#include <string>
#include <sys/syscall.h>
#include <unistd.h>

namespace aidl::android::hardware::power::impl::_6xyun {

inline bool WriteFile(const std::string& path, const std::string& value) {
    FILE* fp = fopen(path.c_str(), "we");
    if (fp == nullptr) {
        return false;
    }
    const bool ok = fputs(value.c_str(), fp) >= 0;
    fclose(fp);
    return ok;
}

inline std::string ReadFile(const std::string& path) {
    char buf[128] = {};
    FILE* fp = fopen(path.c_str(), "re");
    if (fp == nullptr) {
        return {};
    }
    const size_t len = fread(buf, 1, sizeof(buf) - 1, fp);
    fclose(fp);
    buf[len] = '\0';

    std::string value(buf);
    while (!value.empty() &&
           (value.back() == '\n' || value.back() == '\r' || value.back() == ' ')) {
        value.pop_back();
    }
    return value;
}

// bionic 没有导出 sched_attr，按 UAPI 布局自行声明。
struct SchedAttr {
    uint32_t size;
    uint32_t sched_policy;
    uint64_t sched_flags;
    int32_t sched_nice;
    uint32_t sched_priority;
    uint64_t sched_runtime;
    uint64_t sched_deadline;
    uint64_t sched_period;
    uint32_t sched_util_min;
    uint32_t sched_util_max;
};

// SCHED_FLAG_UTIL_CLAMP，见 include/uapi/linux/sched/types.h
constexpr uint64_t kSchedFlagUtilClamp = 0x20;

inline bool SetTaskUclamp(int32_t tid, uint32_t utilMin, uint32_t utilMax) {
    SchedAttr attr{};
    attr.size = sizeof(attr);
    attr.sched_flags = kSchedFlagUtilClamp;
    attr.sched_util_min = utilMin;
    attr.sched_util_max = utilMax;
    return syscall(__NR_sched_setattr, tid, &attr, 0) == 0;
}

}  // namespace aidl::android::hardware::power::impl::_6xyun
