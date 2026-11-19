/*
 * OrangePi-3B (RK3566) Health HAL
 *
 * 直流直接供电、无电池。只覆盖 UpdateHealthInfo()，把硬件事实写出来：
 *   - 外部供电在线（以 AC 在线表达，Android 没有独立的 DC 类型）；
 *   - 电池不存在，容量/电压/电流/温度/健康度不提供编造值；
 *   - 容量等级为 UNSUPPORTED，避免 BatteryService 走低电关机路径。
 */

#include "HealthImpl.h"

namespace aidl::android::hardware::health::impl::_6xyun {

void HealthImpl::UpdateHealthInfo(HealthInfo* health_info) {
    if (health_info == nullptr) {
        return;
    }

    health_info->chargerAcOnline = true;
    health_info->chargerUsbOnline = false;
    health_info->chargerWirelessOnline = false;
    health_info->chargerDockOnline = false;
    health_info->maxChargingCurrentMicroamps = 0;
    health_info->maxChargingVoltageMicrovolts = 0;

    health_info->batteryPresent = false;
    health_info->batteryStatus = BatteryStatus::NOT_CHARGING;
    health_info->batteryHealth = BatteryHealth::UNKNOWN;
    health_info->batteryLevel = 0;
    health_info->batteryVoltageMillivolts = 0;
    health_info->batteryTemperatureTenthsCelsius = 0;
    health_info->batteryCurrentMicroamps = 0;
    health_info->batteryFullChargeUah = 0;
    health_info->batteryChargeCounterUah = 0;
    health_info->batteryCurrentAverageMicroamps = 0;
    health_info->batteryCapacityLevel = BatteryCapacityLevel::UNSUPPORTED;
    health_info->batteryFullChargeDesignCapacityUah = 0;
}

}  // namespace aidl::android::hardware::health::impl::_6xyun
