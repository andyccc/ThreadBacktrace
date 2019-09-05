//
//  mach_symbolic.h
//  ThreadBacktrace
//
//  Created by yans on 2019/9/5.
//

#include <sys/types.h>
#include <dlfcn.h>

/*
// 符号 数据结构
struct nlist {
  union {
    uint32_t n_strx;//符号名在字符串表中的偏移量
  } n_un;
  uint8_t n_type;
  uint8_t n_sect;
  int16_t n_desc;
  uint32_t n_value;//符号在内存中的地址，类似于函数指针
};
*/

/// 解析堆栈符号
bool _dladdr(const uintptr_t address, Dl_info* const info);
