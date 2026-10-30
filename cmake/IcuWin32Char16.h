//
// IcuWin32Char16.h
//
// Force-included on Windows for `test/perf/collationperf/collperf.cpp`.
// That file passes `char16_t *` where the Win32 wide APIs take `wchar_t *`.
//

#ifndef ICU_CMAKE_WIN32_CHAR16_H
#define ICU_CMAKE_WIN32_CHAR16_H

#ifdef __cplusplus

// Keep `min` and `max` out of the rest of the translation unit. This header is included first.
#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>
// `WIN32_LEAN_AND_MEAN` keeps `timeGetTime` out of `windows.h`. This test calls it.
#include <timeapi.h>

inline const wchar_t* IcuCmakeToWide(const char16_t* text) {
#if defined(__clang__) || defined(__GNUC__)
  // Same barrier ICU uses so Clang does not treat `char16_t` and `wchar_t` as non-aliasing.
  asm volatile("" : : "rm"(text) : "memory");
#endif
  return reinterpret_cast<const wchar_t*>(text);
}

inline wchar_t* IcuCmakeToWide(char16_t* text) {
#if defined(__clang__) || defined(__GNUC__)
  asm volatile("" : : "rm"(text) : "memory");
#endif
  return reinterpret_cast<wchar_t*>(text);
}

inline int CompareStringW(LCID locale, DWORD flags, const char16_t* left, int leftLen,
                          const char16_t* right, int rightLen) {
  using Fn = int (WINAPI*)(LCID, DWORD, PCNZWCH, int, PCNZWCH, int);
  return static_cast<Fn>(::CompareStringW)(locale, flags, IcuCmakeToWide(left), leftLen,
                                            IcuCmakeToWide(right), rightLen);
}

inline int LCMapStringW(LCID locale, DWORD flags, const char16_t* src, int srcLen,
                        char16_t* dest, int destLen) {
  using Fn = int (WINAPI*)(LCID, DWORD, LPCWSTR, int, LPWSTR, int);
  return static_cast<Fn>(::LCMapStringW)(locale, flags, IcuCmakeToWide(src), srcLen,
                                          IcuCmakeToWide(dest), destLen);
}

#endif

#endif
