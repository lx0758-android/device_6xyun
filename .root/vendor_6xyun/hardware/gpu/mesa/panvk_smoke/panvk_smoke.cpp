/*
 * PanVK 冒烟测试（Vulkan 1.0）
 *
 * 目的：在把 Mesa PanVK 作为硬件 Vulkan 后端交付时，提供一个可重复的最小渲染用例。
 * 流程：创建 instance/device → 分配离屏 VkImage 与 host-visible 回读缓冲 →
 *       对每个颜色执行 vkCmdClearColorImage → 屏障切换为 TRANSFER_SRC →
 *       vkCmdCopyImageToBuffer → 提交并等待 fence → mmap 回读校验像素。
 *
 * 说明：
 *   - PanVK 在 Bifrost（arch < 10）上只报 Vulkan 1.0，因此本程序按 1.0 编写，
 *     不启用任何设备扩展；HWUI 的 skiavk 路径要求 1.1 以上，不在这里覆盖。
 *   - clear/copy 在 PanVK 内部走运行时 meta 着色器，所以该用例会经过 Bifrost
 *     着色器编译与 GPU 提交，而不只是枚举设备。
 *   - 退出码 0 表示全部颜色校验通过，1 表示失败（具体原因见 stdout / logcat）。
 */

#include <android/log.h>
#include <sys/system_properties.h>

#include <vulkan/vulkan.h>

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

#define LOG_TAG "panvk_smoke"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

constexpr uint32_t kImageWidth = 64;
constexpr uint32_t kImageHeight = 64;
constexpr VkDeviceSize kBytesPerPixel = 4;
constexpr VkDeviceSize kBufferSize = kImageWidth * kImageHeight * kBytesPerPixel;
constexpr uint64_t kSubmitTimeoutNs = 5ull * 1000 * 1000 * 1000;
constexpr int kChannelTolerance = 1;

const char* vk_result_name(VkResult result) {
    switch (result) {
        case VK_SUCCESS:
            return "VK_SUCCESS";
        case VK_NOT_READY:
            return "VK_NOT_READY";
        case VK_TIMEOUT:
            return "VK_TIMEOUT";
        case VK_ERROR_OUT_OF_HOST_MEMORY:
            return "VK_ERROR_OUT_OF_HOST_MEMORY";
        case VK_ERROR_OUT_OF_DEVICE_MEMORY:
            return "VK_ERROR_OUT_OF_DEVICE_MEMORY";
        case VK_ERROR_INITIALIZATION_FAILED:
            return "VK_ERROR_INITIALIZATION_FAILED";
        case VK_ERROR_DEVICE_LOST:
            return "VK_ERROR_DEVICE_LOST";
        case VK_ERROR_MEMORY_MAP_FAILED:
            return "VK_ERROR_MEMORY_MAP_FAILED";
        case VK_ERROR_LAYER_NOT_PRESENT:
            return "VK_ERROR_LAYER_NOT_PRESENT";
        case VK_ERROR_EXTENSION_NOT_PRESENT:
            return "VK_ERROR_EXTENSION_NOT_PRESENT";
        case VK_ERROR_FEATURE_NOT_PRESENT:
            return "VK_ERROR_FEATURE_NOT_PRESENT";
        case VK_ERROR_INCOMPATIBLE_DRIVER:
            return "VK_ERROR_INCOMPATIBLE_DRIVER";
        case VK_ERROR_TOO_MANY_OBJECTS:
            return "VK_ERROR_TOO_MANY_OBJECTS";
        case VK_ERROR_FORMAT_NOT_SUPPORTED:
            return "VK_ERROR_FORMAT_NOT_SUPPORTED";
        default:
            return "VK_ERROR_OTHER";
    }
}

uint8_t to_unorm(float value) {
    if (value <= 0.0f) {
        return 0;
    }
    if (value >= 1.0f) {
        return 255;
    }
    return static_cast<uint8_t>(value * 255.0f + 0.5f);
}

int abs_diff(uint8_t a, uint8_t b) {
    return a > b ? a - b : b - a;
}

struct ClearCase {
    const char* name;
    float r;
    float g;
    float b;
    float a;
};

class PanvkSmoke {
  public:
    ~PanvkSmoke() { cleanup(); }

    bool run();

  private:
    bool create_instance();
    bool pick_physical_device();
    bool create_device();
    bool create_target();
    bool submit_case(const ClearCase& clear_case);
    bool verify_pixels(const ClearCase& clear_case, const uint8_t* pixels) const;

    void image_barrier(VkCommandBuffer command_buffer, VkImageLayout old_layout,
                       VkImageLayout new_layout, VkAccessFlags src_access,
                       VkAccessFlags dst_access, VkPipelineStageFlags src_stage,
                       VkPipelineStageFlags dst_stage);
    static uint32_t find_memory_type(const VkPhysicalDeviceMemoryProperties& memory_properties,
                                     uint32_t type_bits, VkMemoryPropertyFlags required);
    void cleanup();

    VkInstance instance_ = VK_NULL_HANDLE;
    VkPhysicalDevice physical_device_ = VK_NULL_HANDLE;
    VkPhysicalDeviceProperties properties_{};
    VkDevice device_ = VK_NULL_HANDLE;
    VkQueue queue_ = VK_NULL_HANDLE;
    uint32_t queue_family_ = 0;

    VkCommandPool command_pool_ = VK_NULL_HANDLE;
    VkCommandBuffer command_buffer_ = VK_NULL_HANDLE;
    VkFence fence_ = VK_NULL_HANDLE;

    VkImage image_ = VK_NULL_HANDLE;
    VkDeviceMemory image_memory_ = VK_NULL_HANDLE;
    VkBuffer buffer_ = VK_NULL_HANDLE;
    VkDeviceMemory buffer_memory_ = VK_NULL_HANDLE;
    void* mapped_ = nullptr;

    VkImageLayout image_layout_ = VK_IMAGE_LAYOUT_UNDEFINED;
};

bool PanvkSmoke::create_instance() {
    VkApplicationInfo application_info{};
    application_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    application_info.pApplicationName = "panvk_smoke";
    application_info.applicationVersion = 1;
    application_info.pEngineName = "panvk_smoke";
    application_info.engineVersion = 1;
    application_info.apiVersion = VK_API_VERSION_1_0;

    VkInstanceCreateInfo create_info{};
    create_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    create_info.pApplicationInfo = &application_info;

    const VkResult result = vkCreateInstance(&create_info, nullptr, &instance_);
    if (result != VK_SUCCESS) {
        LOGE("vkCreateInstance failed: %s (%d)", vk_result_name(result), result);
        return false;
    }
    return true;
}

bool PanvkSmoke::pick_physical_device() {
    uint32_t device_count = 0;
    VkResult result = vkEnumeratePhysicalDevices(instance_, &device_count, nullptr);
    if (result != VK_SUCCESS || device_count == 0) {
        char vulkan_hardware[PROP_VALUE_MAX] = {};
        char panvk_enable[PROP_VALUE_MAX] = {};
        __system_property_get("ro.hardware.vulkan", vulkan_hardware);
        __system_property_get("debug.mesa.pan.i.want.a.broken.vulkan.driver", panvk_enable);

        LOGE("no Vulkan physical device: result=%s (%d) count=%u", vk_result_name(result),
             result, device_count);
        LOGE("ro.hardware.vulkan=%s, panvk enable prop=%s",
             vulkan_hardware[0] ? vulkan_hardware : "(empty)",
             panvk_enable[0] ? panvk_enable : "(unset)");
        LOGE("hint: PanVK on Bifrost requires "
             "debug.mesa.pan.i.want.a.broken.vulkan.driver=1");
        return false;
    }

    std::vector<VkPhysicalDevice> devices(device_count);
    result = vkEnumeratePhysicalDevices(instance_, &device_count, devices.data());
    if (result != VK_SUCCESS || device_count == 0) {
        LOGE("vkEnumeratePhysicalDevices(2) failed: %s (%d)", vk_result_name(result), result);
        return false;
    }

    physical_device_ = devices[0];
    vkGetPhysicalDeviceProperties(physical_device_, &properties_);

    printf("device      : %s\n", properties_.deviceName);
    printf("vendorID    : 0x%04x\n", properties_.vendorID);
    printf("deviceID    : 0x%04x\n", properties_.deviceID);
    printf("apiVersion  : %u.%u.%u\n", VK_VERSION_MAJOR(properties_.apiVersion),
           VK_VERSION_MINOR(properties_.apiVersion), VK_VERSION_PATCH(properties_.apiVersion));
    printf("driverVersion: %u.%u.%u\n", VK_VERSION_MAJOR(properties_.driverVersion),
           VK_VERSION_MINOR(properties_.driverVersion),
           VK_VERSION_PATCH(properties_.driverVersion));
    LOGI("physical device: %s (api %u.%u.%u)", properties_.deviceName,
         VK_VERSION_MAJOR(properties_.apiVersion), VK_VERSION_MINOR(properties_.apiVersion),
         VK_VERSION_PATCH(properties_.apiVersion));

    uint32_t family_count = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(physical_device_, &family_count, nullptr);
    if (family_count == 0) {
        LOGE("no queue family reported");
        return false;
    }

    std::vector<VkQueueFamilyProperties> families(family_count);
    vkGetPhysicalDeviceQueueFamilyProperties(physical_device_, &family_count, families.data());

    for (uint32_t i = 0; i < family_count; ++i) {
        if ((families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0) {
            queue_family_ = i;
            printf("queueFamily : %u (graphics, %u queues)\n", i, families[i].queueCount);
            return true;
        }
    }

    LOGE("no graphics queue family available");
    return false;
}

bool PanvkSmoke::create_device() {
    const float queue_priority = 1.0f;

    VkDeviceQueueCreateInfo queue_info{};
    queue_info.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queue_info.queueFamilyIndex = queue_family_;
    queue_info.queueCount = 1;
    queue_info.pQueuePriorities = &queue_priority;

    VkDeviceCreateInfo create_info{};
    create_info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    create_info.queueCreateInfoCount = 1;
    create_info.pQueueCreateInfos = &queue_info;

    const VkResult result = vkCreateDevice(physical_device_, &create_info, nullptr, &device_);
    if (result != VK_SUCCESS) {
        LOGE("vkCreateDevice failed: %s (%d)", vk_result_name(result), result);
        return false;
    }

    vkGetDeviceQueue(device_, queue_family_, 0, &queue_);
    if (queue_ == VK_NULL_HANDLE) {
        LOGE("vkGetDeviceQueue returned VK_NULL_HANDLE");
        return false;
    }
    return true;
}

uint32_t PanvkSmoke::find_memory_type(const VkPhysicalDeviceMemoryProperties& memory_properties,
                                      uint32_t type_bits,
                                      VkMemoryPropertyFlags required) {
    for (uint32_t i = 0; i < memory_properties.memoryTypeCount; ++i) {
        const bool supported = (type_bits & (1u << i)) != 0;
        const bool matches =
            (memory_properties.memoryTypes[i].propertyFlags & required) == required;
        if (supported && matches) {
            return i;
        }
    }
    return UINT32_MAX;
}

bool PanvkSmoke::create_target() {
    VkPhysicalDeviceMemoryProperties memory_properties{};
    vkGetPhysicalDeviceMemoryProperties(physical_device_, &memory_properties);

    VkImageCreateInfo image_info{};
    image_info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    image_info.imageType = VK_IMAGE_TYPE_2D;
    image_info.format = VK_FORMAT_R8G8B8A8_UNORM;
    image_info.extent.width = kImageWidth;
    image_info.extent.height = kImageHeight;
    image_info.extent.depth = 1;
    image_info.mipLevels = 1;
    image_info.arrayLayers = 1;
    image_info.samples = VK_SAMPLE_COUNT_1_BIT;
    image_info.tiling = VK_IMAGE_TILING_OPTIMAL;
    image_info.usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
                       VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    image_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    image_info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    VkResult result = vkCreateImage(device_, &image_info, nullptr, &image_);
    if (result != VK_SUCCESS) {
        LOGE("vkCreateImage failed: %s (%d)", vk_result_name(result), result);
        return false;
    }

    VkMemoryRequirements image_requirements{};
    vkGetImageMemoryRequirements(device_, image_, &image_requirements);

    const uint32_t image_type = find_memory_type(memory_properties,
                                                 image_requirements.memoryTypeBits,
                                                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (image_type == UINT32_MAX) {
        LOGE("no DEVICE_LOCAL memory type for image");
        return false;
    }

    VkMemoryAllocateInfo image_allocate{};
    image_allocate.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    image_allocate.allocationSize = image_requirements.size;
    image_allocate.memoryTypeIndex = image_type;

    result = vkAllocateMemory(device_, &image_allocate, nullptr, &image_memory_);
    if (result != VK_SUCCESS) {
        LOGE("vkAllocateMemory(image) failed: %s (%d)", vk_result_name(result), result);
        return false;
    }
    result = vkBindImageMemory(device_, image_, image_memory_, 0);
    if (result != VK_SUCCESS) {
        LOGE("vkBindImageMemory failed: %s (%d)", vk_result_name(result), result);
        return false;
    }

    VkBufferCreateInfo buffer_info{};
    buffer_info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    buffer_info.size = kBufferSize;
    buffer_info.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    buffer_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    result = vkCreateBuffer(device_, &buffer_info, nullptr, &buffer_);
    if (result != VK_SUCCESS) {
        LOGE("vkCreateBuffer failed: %s (%d)", vk_result_name(result), result);
        return false;
    }

    VkMemoryRequirements buffer_requirements{};
    vkGetBufferMemoryRequirements(device_, buffer_, &buffer_requirements);

    const uint32_t buffer_type = find_memory_type(
        memory_properties, buffer_requirements.memoryTypeBits,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    if (buffer_type == UINT32_MAX) {
        LOGE("no HOST_VISIBLE|HOST_COHERENT memory type for readback buffer");
        return false;
    }

    VkMemoryAllocateInfo buffer_allocate{};
    buffer_allocate.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    buffer_allocate.allocationSize = buffer_requirements.size;
    buffer_allocate.memoryTypeIndex = buffer_type;

    result = vkAllocateMemory(device_, &buffer_allocate, nullptr, &buffer_memory_);
    if (result != VK_SUCCESS) {
        LOGE("vkAllocateMemory(buffer) failed: %s (%d)", vk_result_name(result), result);
        return false;
    }
    result = vkBindBufferMemory(device_, buffer_, buffer_memory_, 0);
    if (result != VK_SUCCESS) {
        LOGE("vkBindBufferMemory failed: %s (%d)", vk_result_name(result), result);
        return false;
    }

    result = vkMapMemory(device_, buffer_memory_, 0, VK_WHOLE_SIZE, 0, &mapped_);
    if (result != VK_SUCCESS) {
        LOGE("vkMapMemory failed: %s (%d)", vk_result_name(result), result);
        mapped_ = nullptr;
        return false;
    }
    memset(mapped_, 0, static_cast<size_t>(kBufferSize));

    VkCommandPoolCreateInfo pool_info{};
    pool_info.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    pool_info.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    pool_info.queueFamilyIndex = queue_family_;

    result = vkCreateCommandPool(device_, &pool_info, nullptr, &command_pool_);
    if (result != VK_SUCCESS) {
        LOGE("vkCreateCommandPool failed: %s (%d)", vk_result_name(result), result);
        return false;
    }

    VkCommandBufferAllocateInfo command_allocate{};
    command_allocate.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    command_allocate.commandPool = command_pool_;
    command_allocate.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    command_allocate.commandBufferCount = 1;

    result = vkAllocateCommandBuffers(device_, &command_allocate, &command_buffer_);
    if (result != VK_SUCCESS) {
        LOGE("vkAllocateCommandBuffers failed: %s (%d)", vk_result_name(result), result);
        return false;
    }

    VkFenceCreateInfo fence_info{};
    fence_info.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;

    result = vkCreateFence(device_, &fence_info, nullptr, &fence_);
    if (result != VK_SUCCESS) {
        LOGE("vkCreateFence failed: %s (%d)", vk_result_name(result), result);
        return false;
    }

    return true;
}

void PanvkSmoke::image_barrier(VkCommandBuffer command_buffer, VkImageLayout old_layout,
                               VkImageLayout new_layout, VkAccessFlags src_access,
                               VkAccessFlags dst_access, VkPipelineStageFlags src_stage,
                               VkPipelineStageFlags dst_stage) {
    VkImageMemoryBarrier barrier{};
    barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.oldLayout = old_layout;
    barrier.newLayout = new_layout;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = image_;
    barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    barrier.subresourceRange.baseMipLevel = 0;
    barrier.subresourceRange.levelCount = 1;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount = 1;
    barrier.srcAccessMask = src_access;
    barrier.dstAccessMask = dst_access;

    vkCmdPipelineBarrier(command_buffer, src_stage, dst_stage, 0, 0, nullptr, 0, nullptr, 1,
                         &barrier);
    image_layout_ = new_layout;
}

bool PanvkSmoke::verify_pixels(const ClearCase& clear_case, const uint8_t* pixels) const {
    const uint8_t expected[kBytesPerPixel] = {to_unorm(clear_case.r), to_unorm(clear_case.g),
                                             to_unorm(clear_case.b), to_unorm(clear_case.a)};

    const uint32_t sample_points[3][2] = {
        {0, 0},
        {kImageWidth / 2, kImageHeight / 2},
        {kImageWidth - 1, kImageHeight - 1},
    };

    bool ok = true;
    for (uint32_t i = 0; i < 3; ++i) {
        const uint32_t x = sample_points[i][0];
        const uint32_t y = sample_points[i][1];
        const uint8_t* pixel = pixels + (static_cast<size_t>(y) * kImageWidth + x) * kBytesPerPixel;

        bool pixel_ok = true;
        for (uint32_t c = 0; c < kBytesPerPixel; ++c) {
            if (abs_diff(pixel[c], expected[c]) > kChannelTolerance) {
                pixel_ok = false;
            }
        }

        printf("  (%u,%u) = %02x %02x %02x %02x (expect %02x %02x %02x %02x) %s\n", x, y,
               pixel[0], pixel[1], pixel[2], pixel[3], expected[0], expected[1], expected[2],
               expected[3], pixel_ok ? "ok" : "MISMATCH");
        if (!pixel_ok) {
            ok = false;
        }
    }

    if (!ok) {
        LOGE("clear case '%s' readback mismatch", clear_case.name);
    }
    return ok;
}

bool PanvkSmoke::submit_case(const ClearCase& clear_case) {
    VkResult result = vkResetCommandBuffer(command_buffer_, 0);
    if (result != VK_SUCCESS) {
        LOGE("vkResetCommandBuffer failed: %s (%d)", vk_result_name(result), result);
        return false;
    }

    VkCommandBufferBeginInfo begin_info{};
    begin_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    begin_info.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

    result = vkBeginCommandBuffer(command_buffer_, &begin_info);
    if (result != VK_SUCCESS) {
        LOGE("vkBeginCommandBuffer failed: %s (%d)", vk_result_name(result), result);
        return false;
    }

    image_barrier(command_buffer_, image_layout_, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 0,
                  VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                  VK_PIPELINE_STAGE_TRANSFER_BIT);

    VkClearColorValue color{};
    color.float32[0] = clear_case.r;
    color.float32[1] = clear_case.g;
    color.float32[2] = clear_case.b;
    color.float32[3] = clear_case.a;

    VkImageSubresourceRange clear_range{};
    clear_range.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    clear_range.baseMipLevel = 0;
    clear_range.levelCount = 1;
    clear_range.baseArrayLayer = 0;
    clear_range.layerCount = 1;

    vkCmdClearColorImage(command_buffer_, image_, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &color, 1,
                         &clear_range);

    image_barrier(command_buffer_, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                  VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_ACCESS_TRANSFER_WRITE_BIT,
                  VK_ACCESS_TRANSFER_READ_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
                  VK_PIPELINE_STAGE_TRANSFER_BIT);

    VkBufferImageCopy copy_region{};
    copy_region.bufferOffset = 0;
    copy_region.bufferRowLength = 0;
    copy_region.bufferImageHeight = 0;
    copy_region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    copy_region.imageSubresource.mipLevel = 0;
    copy_region.imageSubresource.baseArrayLayer = 0;
    copy_region.imageSubresource.layerCount = 1;
    copy_region.imageOffset.x = 0;
    copy_region.imageOffset.y = 0;
    copy_region.imageOffset.z = 0;
    copy_region.imageExtent.width = kImageWidth;
    copy_region.imageExtent.height = kImageHeight;
    copy_region.imageExtent.depth = 1;

    vkCmdCopyImageToBuffer(command_buffer_, image_, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, buffer_, 1,
                           &copy_region);

    VkBufferMemoryBarrier buffer_barrier{};
    buffer_barrier.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
    buffer_barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    buffer_barrier.dstAccessMask = VK_ACCESS_HOST_READ_BIT;
    buffer_barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    buffer_barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    buffer_barrier.buffer = buffer_;
    buffer_barrier.offset = 0;
    buffer_barrier.size = VK_WHOLE_SIZE;

    vkCmdPipelineBarrier(command_buffer_, VK_PIPELINE_STAGE_TRANSFER_BIT,
                         VK_PIPELINE_STAGE_HOST_BIT, 0, 0, nullptr, 1, &buffer_barrier, 0,
                         nullptr);

    result = vkEndCommandBuffer(command_buffer_);
    if (result != VK_SUCCESS) {
        LOGE("vkEndCommandBuffer failed: %s (%d)", vk_result_name(result), result);
        return false;
    }

    result = vkResetFences(device_, 1, &fence_);
    if (result != VK_SUCCESS) {
        LOGE("vkResetFences failed: %s (%d)", vk_result_name(result), result);
        return false;
    }

    VkSubmitInfo submit_info{};
    submit_info.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submit_info.commandBufferCount = 1;
    submit_info.pCommandBuffers = &command_buffer_;

    const auto start = std::chrono::steady_clock::now();
    result = vkQueueSubmit(queue_, 1, &submit_info, fence_);
    if (result != VK_SUCCESS) {
        LOGE("vkQueueSubmit failed: %s (%d)", vk_result_name(result), result);
        return false;
    }

    result = vkWaitForFences(device_, 1, &fence_, VK_TRUE, kSubmitTimeoutNs);
    const auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                                std::chrono::steady_clock::now() - start)
                                .count();
    if (result != VK_SUCCESS) {
        LOGE("vkWaitForFences failed: %s (%d) after %lld ms", vk_result_name(result), result,
             static_cast<long long>(elapsed_ms));
        return false;
    }

    VkMappedMemoryRange mapped_range{};
    mapped_range.sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE;
    mapped_range.memory = buffer_memory_;
    mapped_range.offset = 0;
    mapped_range.size = VK_WHOLE_SIZE;
    vkInvalidateMappedMemoryRanges(device_, 1, &mapped_range);

    printf("case '%s': submitted in %lld ms\n", clear_case.name,
           static_cast<long long>(elapsed_ms));
    return verify_pixels(clear_case, static_cast<const uint8_t*>(mapped_));
}

bool PanvkSmoke::run() {
    char vulkan_hardware[PROP_VALUE_MAX] = {};
    char panvk_enable[PROP_VALUE_MAX] = {};
    __system_property_get("ro.hardware.vulkan", vulkan_hardware);
    __system_property_get("debug.mesa.pan.i.want.a.broken.vulkan.driver", panvk_enable);
    printf("ro.hardware.vulkan=%s\n", vulkan_hardware[0] ? vulkan_hardware : "(empty)");
    printf("panvk enable prop=%s\n", panvk_enable[0] ? panvk_enable : "(unset)");

    if (!create_instance() || !pick_physical_device() || !create_device() || !create_target()) {
        return false;
    }

    const ClearCase cases[] = {
        {"red", 1.0f, 0.0f, 0.0f, 1.0f},
        {"green", 0.0f, 1.0f, 0.0f, 1.0f},
        {"mixed", 0.25f, 0.5f, 0.75f, 1.0f},
    };

    for (const ClearCase& clear_case : cases) {
        if (!submit_case(clear_case)) {
            return false;
        }
    }

    printf("RESULT: PASS\n");
    LOGI("all clear/copy cases passed");
    return true;
}

void PanvkSmoke::cleanup() {
    if (device_ != VK_NULL_HANDLE) {
        vkDeviceWaitIdle(device_);
    }
    if (mapped_ != nullptr) {
        vkUnmapMemory(device_, buffer_memory_);
        mapped_ = nullptr;
    }
    if (fence_ != VK_NULL_HANDLE) {
        vkDestroyFence(device_, fence_, nullptr);
        fence_ = VK_NULL_HANDLE;
    }
    if (command_pool_ != VK_NULL_HANDLE) {
        vkDestroyCommandPool(device_, command_pool_, nullptr);
        command_pool_ = VK_NULL_HANDLE;
        command_buffer_ = VK_NULL_HANDLE;
    }
    if (buffer_ != VK_NULL_HANDLE) {
        vkDestroyBuffer(device_, buffer_, nullptr);
        buffer_ = VK_NULL_HANDLE;
    }
    if (buffer_memory_ != VK_NULL_HANDLE) {
        vkFreeMemory(device_, buffer_memory_, nullptr);
        buffer_memory_ = VK_NULL_HANDLE;
    }
    if (image_ != VK_NULL_HANDLE) {
        vkDestroyImage(device_, image_, nullptr);
        image_ = VK_NULL_HANDLE;
    }
    if (image_memory_ != VK_NULL_HANDLE) {
        vkFreeMemory(device_, image_memory_, nullptr);
        image_memory_ = VK_NULL_HANDLE;
    }
    if (device_ != VK_NULL_HANDLE) {
        vkDestroyDevice(device_, nullptr);
        device_ = VK_NULL_HANDLE;
    }
    if (instance_ != VK_NULL_HANDLE) {
        vkDestroyInstance(instance_, nullptr);
        instance_ = VK_NULL_HANDLE;
    }
}

}  // namespace

int main() {
    printf("panvk_smoke: Vulkan 1.0 offscreen clear/copy test\n");
    PanvkSmoke smoke;
    if (!smoke.run()) {
        printf("RESULT: FAIL\n");
        return 1;
    }
    return 0;
}
