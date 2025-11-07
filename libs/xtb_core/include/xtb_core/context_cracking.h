// Copyright (c) Epic Games Tools
// Licensed under the MIT license (https://opensource.org/license/mit/)

#ifndef BASE_CONTEXT_CRACKING_H
#define BASE_CONTEXT_CRACKING_H

////////////////////////////////
//~ rjf: Clang OS/Arch Cracking

#if defined(__clang__)

# define XTB_COMPILER_CLANG 1

# if defined(_WIN32)
#  define XTB_OS_WINDOWS 1
# elif defined(__gnu_linux__) || defined(__linux__)
#  define XTB_OS_LINUX 1
# elif defined(__APPLE__) && defined(__MACH__)
#  define XTB_OS_MAC 1
# else
#  error This compiler/OS combo is not supported.
# endif

# if defined(__amd64__) || defined(__amd64) || defined(__x86_64__) || defined(__x86_64)
#  define XTB_ARCH_X64 1
# elif defined(i386) || defined(__i386) || defined(__i386__)
#  define XTB_ARCH_X86 1
# elif defined(__aarch64__)
#  define XTB_ARCH_ARM64 1
# elif defined(__arm__)
#  define XTB_ARCH_ARM32 1
# else
#  error Architecture not supported.
# endif

////////////////////////////////
//~ rjf: MSVC OS/Arch Cracking

#elif defined(_MSC_VER)

# define XTB_COMPILER_MSVC 1

# if _MSC_VER >= 1920
#  define XTB_COMPILER_MSVC_YEAR 2019
# elif _MSC_VER >= 1910
#  define XTB_COMPILER_MSVC_YEAR 2017
# elif _MSC_VER >= 1900
#  define XTB_COMPILER_MSVC_YEAR 2015
# elif _MSC_VER >= 1800
#  define XTB_COMPILER_MSVC_YEAR 2013
# elif _MSC_VER >= 1700
#  define XTB_COMPILER_MSVC_YEAR 2012
# elif _MSC_VER >= 1600
#  define XTB_COMPILER_MSVC_YEAR 2010
# elif _MSC_VER >= 1500
#  define XTB_COMPILER_MSVC_YEAR 2008
# elif _MSC_VER >= 1400
#  define XTB_COMPILER_MSVC_YEAR 2005
# else
#  define XTB_COMPILER_MSVC_YEAR 0
# endif

# if defined(_WIN32)
#  define XTB_OS_WINDOWS 1
# else
#  error This compiler/OS combo is not supported.
# endif

# if defined(_M_AMD64)
#  define XTB_ARCH_X64 1
# elif defined(_M_IX86)
#  define XTB_ARCH_X86 1
# elif defined(_M_ARM64)
#  define XTB_ARCH_ARM64 1
# elif defined(_M_ARM)
#  define XTB_ARCH_ARM32 1
# else
#  error Architecture not supported.
# endif

////////////////////////////////
//~ rjf: GCC OS/Arch Cracking

#elif defined(__GNUC__) || defined(__GNUG__)

# define XTB_COMPILER_GCC 1

# if defined(__gnu_linux__) || defined(__linux__)
#  define XTB_OS_LINUX 1
# else
#  error This compiler/OS combo is not supported.
# endif

# if defined(__amd64__) || defined(__amd64) || defined(__x86_64__) || defined(__x86_64)
#  define XTB_ARCH_X64 1
# elif defined(i386) || defined(__i386) || defined(__i386__)
#  define XTB_ARCH_X86 1
# elif defined(__aarch64__)
#  define XTB_ARCH_ARM64 1
# elif defined(__arm__)
#  define XTB_ARCH_ARM32 1
# else
#  error Architecture not supported.
# endif

#else
# error Compiler not supported.
#endif

////////////////////////////////
//~ rjf: Arch Cracking

#if defined(XTB_ARCH_X64)
# define XTB_ARCH_64BIT 1
#elif defined(XTB_ARCH_X86)
# define XTB_ARCH_32BIT 1
#endif

#if XTB_ARCH_ARM32 || XTB_ARCH_ARM64 || XTB_ARCH_X64 || XTB_ARCH_X86
# define XTB_ARCH_LITTLE_ENDIAN 1
#else
# error Endianness of this architecture not understood by context cracker.
#endif

////////////////////////////////
//~ rjf: Language Cracking

#if defined(__cplusplus)
# define XTB_LANG_CPP 1
#else
# define XTB_LANG_C 1
#endif

////////////////////////////////
//~ rjf: Zero All Undefined Options

#if !defined(XTB_ARCH_32BIT)
# define XTB_ARCH_32BIT 0
#endif
#if !defined(XTB_ARCH_64BIT)
# define XTB_ARCH_64BIT 0
#endif
#if !defined(XTB_ARCH_X64)
# define XTB_ARCH_X64 0
#endif
#if !defined(XTB_ARCH_X86)
# define XTB_ARCH_X86 0
#endif
#if !defined(XTB_ARCH_ARM64)
# define XTB_ARCH_ARM64 0
#endif
#if !defined(XTB_ARCH_ARM32)
# define XTB_ARCH_ARM32 0
#endif
#if !defined(XTB_COMPILER_MSVC)
# define XTB_COMPILER_MSVC 0
#endif
#if !defined(XTB_COMPILER_GCC)
# define XTB_COMPILER_GCC 0
#endif
#if !defined(XTB_COMPILER_CLANG)
# define XTB_COMPILER_CLANG 0
#endif
#if !defined(XTB_OS_WINDOWS)
# define XTB_OS_WINDOWS 0
#endif
#if !defined(XTB_OS_LINUX)
# define XTB_OS_LINUX 0
#endif
#if !defined(XTB_OS_MAC)
# define XTB_OS_MAC 0
#endif
#if !defined(XTB_LANG_CPP)
# define XTB_LANG_CPP 0
#endif
#if !defined(XTB_LANG_C)
# define XTB_LANG_C 0
#endif

////////////////////////////////
//~ rjf: Unsupported Errors

#if XTB_ARCH_X86
# error You tried to build in x86 (32 bit) mode, but currently, only building in x64 (64 bit) mode is supported.
#endif
#if !XTB_ARCH_X64
# error You tried to build with an unsupported architecture. Currently, only building in x64 mode is supported.
#endif

#endif // BASE_CONTEXT_CRACKING_H
