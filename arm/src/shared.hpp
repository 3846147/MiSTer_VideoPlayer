#pragma once
#include <cstdint>

namespace vp {
constexpr std::uint64_t MEM_BASE = 0x3A000000ULL;
constexpr std::size_t   MEM_LEN  = 0x00400000;
constexpr std::size_t OFF_CONTROL = 0x00;
constexpr std::size_t OFF_JOY     = 0x08;
constexpr std::size_t OFF_STATUS0 = 0x10;
constexpr std::size_t OFF_HEART   = 0x18;
constexpr std::size_t OFF_STATUS1 = 0x20;
constexpr std::size_t OFF_MOUNT   = 0x28;
constexpr std::size_t OFF_FB0     = 0x00100000;
constexpr std::size_t OFF_FB1     = 0x00196000;
constexpr std::size_t FB_W = 640;
constexpr std::size_t FB_H = 480;
constexpr std::size_t FB_BYTES = FB_W * FB_H * 2;
constexpr std::uint32_t HEART_MAGIC = 0x56504C59; // VPLY
}
