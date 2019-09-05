//
//  backtrace.c
//  ThreadBacktrace
//
//  Created by yans on 2019/9/5.
//

#include "backtrace_help.h"

/// 主线程 ID 利用 C 构造函数设置
static mach_port_t _main_thread_id;

__attribute__((constructor)) static
void _setup_main_thread() {
    _main_thread_id = mach_thread_self();
}

/// 获取主线程 ID 
mach_port_t get_mach_main_thread() {
    return _main_thread_id;
}

bool has_dli_fname(struct dl_info info) {
    return info.dli_fname != NULL;
}
