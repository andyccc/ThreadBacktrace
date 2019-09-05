//
//  mach_symbolic.c
//  ThreadBacktrace
//
//  Created by yans on 2019/9/5.
//

#include "mach_symbolic.h"
#include <mach/mach.h>
#include <dlfcn.h>
#include <pthread.h>
#include <sys/types.h>
#include <limits.h>
#include <string.h>
#include <mach-o/dyld.h>
#include <mach-o/nlist.h>

#include <mach-o/getsect.h>
#include <objc/runtime.h>
#include <stdio.h>

#pragma mark - 平台定义
#ifdef __LP64__

typedef struct mach_header_64 mach_header_t;
typedef struct segment_command_64 segment_command_t;
typedef struct section_64 section_t;
typedef struct nlist_64 nlist_t;

#else

typedef struct mach_header mach_header_t;
typedef struct segment_command segment_command_t;
typedef struct section section_t;
typedef struct nlist nlist_t;

#endif

#pragma mark - 声明
/// 获取 Mach-O 中的第一条 load commadn
static uintptr_t _firstCmdAfterHeader(const struct mach_header* const header);
/// 获取 address 所属的 image index
static uint32_t _imageIndexContainingAddress(const uintptr_t address);
/// Mach-O 段基址
static uintptr_t _segmentBaseOfImageIndex(const uint32_t idx);

#pragma mark - 实现
/// 解析堆栈符号
bool _dladdr(const uintptr_t address, Dl_info* const info)
{
    info->dli_fname = NULL;
    info->dli_fbase = NULL;
    info->dli_sname = NULL;
    info->dli_saddr = NULL;

    const uint32_t idx = _imageIndexContainingAddress(address);
    if(idx == UINT_MAX) {
        return false;
    }
    const struct mach_header* header = _dyld_get_image_header(idx);
    const uintptr_t imageVMAddrSlide = (uintptr_t)_dyld_get_image_vmaddr_slide(idx);
    const uintptr_t addressWithSlide = address - imageVMAddrSlide;
    const uintptr_t segmentBase = _segmentBaseOfImageIndex(idx) + imageVMAddrSlide;
    if(segmentBase == 0) {
        return false;
    }

    info->dli_fname = _dyld_get_image_name(idx);
    info->dli_fbase = (void*)header;

    // Find symbol tables and get whichever symbol is closest to the address.
    const nlist_t* bestMatch = NULL;
    uintptr_t bestDistance = ULONG_MAX;
    uintptr_t cmdPtr = _firstCmdAfterHeader(header);
    if(cmdPtr == 0) {
        return false;
    }
    for(uint32_t iCmd = 0; iCmd < header->ncmds; iCmd++) {
        const struct load_command* loadCmd = (struct load_command*)cmdPtr;
        if(loadCmd->cmd == LC_SYMTAB) {
            const struct symtab_command* symtabCmd = (struct symtab_command*)cmdPtr;
            const nlist_t* symbolTable = (nlist_t*)(segmentBase + symtabCmd->symoff);
            const uintptr_t stringTable = segmentBase + symtabCmd->stroff;

            for(uint32_t iSym = 0; iSym < symtabCmd->nsyms; iSym++) {
                // If n_value is 0, the symbol refers to an external object.
                if(symbolTable[iSym].n_value != 0) {
                    uintptr_t symbolBase = symbolTable[iSym].n_value;
                    uintptr_t currentDistance = addressWithSlide - symbolBase;
                    if((addressWithSlide >= symbolBase) &&
                       (currentDistance <= bestDistance)) {
                        bestMatch = symbolTable + iSym;
                        bestDistance = currentDistance;
                    }
                }
            }
            if(bestMatch != NULL) {
                info->dli_saddr = (void*)(bestMatch->n_value + imageVMAddrSlide);
                if(bestMatch->n_desc == 16) {
                    // This image has been stripped. The name is meaningless, and
                    // almost certainly resolves to "_mh_execute_header"
                    info->dli_sname = NULL;
                }
                else {
                    info->dli_sname = (char*)((intptr_t)stringTable + (intptr_t)bestMatch->n_un.n_strx);
                    if(*info->dli_sname == '_') {
                        info->dli_sname++;
                    }
                }
                break;
            }
        }
        cmdPtr += loadCmd->cmdsize;
    }
    
    return true;
}
/**
 通过遍历获取Image Mach-O Header头部信息及其加载命令来获取所属的地址空间范围来判断是否位于当前Image
 */
/// 获取 address 所属的 image index
static uint32_t _imageIndexContainingAddress(const uintptr_t address)
{
    const uint32_t imageCount = _dyld_image_count();
    const struct mach_header* header = 0;
    
    for(uint32_t iImg = 0; iImg < imageCount; iImg++)
    {
        header = _dyld_get_image_header(iImg);
        if(header != NULL)
        {
            // Look for a segment command with this address within its range.
            uintptr_t addressWSlide = address - (uintptr_t)_dyld_get_image_vmaddr_slide(iImg);
            uintptr_t cmdPtr = _firstCmdAfterHeader(header);
            if(cmdPtr == 0)
            {
                continue;
            }
            for(uint32_t iCmd = 0; iCmd < header->ncmds; iCmd++)
            {
                const struct load_command* loadCmd = (struct load_command*)cmdPtr;
                if(loadCmd->cmd == LC_SEGMENT)
                {
                    const struct segment_command* segCmd = (struct segment_command*)cmdPtr;
                    if(addressWSlide >= segCmd->vmaddr &&
                       addressWSlide < segCmd->vmaddr + segCmd->vmsize)
                    {
                        return iImg;
                    }
                }
                else if(loadCmd->cmd == LC_SEGMENT_64)
                {
                    const struct segment_command_64* segCmd = (struct segment_command_64*)cmdPtr;
                    if(addressWSlide >= segCmd->vmaddr &&
                       addressWSlide < segCmd->vmaddr + segCmd->vmsize)
                    {
                        return iImg;
                    }
                }
                cmdPtr += loadCmd->cmdsize;
            }
        }
    }
    return UINT_MAX;
}


/*
 Mach-O基址
 uintptr_t linkedit_base = linkedit_segment->vmadd - linkedit_segment->fileoff + (unintptr)slide
  Linkedit虚拟地址 = PAGEZERO + FileOffset
  MachO地址 = PAGEZERO + ASLR
  MachO文件地址 = Linkedit虚拟地址 - FileOffset + ASLR(slide)
 */
/// Mach-O 段基址
static uintptr_t _segmentBaseOfImageIndex(const uint32_t idx)
{
    const struct mach_header* header = _dyld_get_image_header(idx);
    
    // Look for a segment command and return the file image address.
    uintptr_t cmdPtr = _firstCmdAfterHeader(header);
    if(cmdPtr == 0)
    {
        return 0;
    }
    for(uint32_t i = 0;i < header->ncmds; i++)
    {
        const struct load_command* loadCmd = (struct load_command*)cmdPtr;
        if(loadCmd->cmd == LC_SEGMENT)
        {
            const struct segment_command* segmentCmd = (struct segment_command*)cmdPtr;
            if(strcmp(segmentCmd->segname, SEG_LINKEDIT) == 0)
            {
                return segmentCmd->vmaddr - segmentCmd->fileoff;
            }
        }
        else if(loadCmd->cmd == LC_SEGMENT_64)
        {
            const struct segment_command_64* segmentCmd = (struct segment_command_64*)cmdPtr;
            if(strcmp(segmentCmd->segname, SEG_LINKEDIT) == 0)
            {
                return (uintptr_t)(segmentCmd->vmaddr - segmentCmd->fileoff);
            }
        }
        cmdPtr += loadCmd->cmdsize;
    }
    
    return 0;
}

/// 获取 Mach-O 中的第一条 load commadn
static uintptr_t _firstCmdAfterHeader(const struct mach_header* const header)
{
    switch(header->magic)
    {
        case MH_MAGIC:
        case MH_CIGAM:
            return (uintptr_t)(header + 1);
        case MH_MAGIC_64:
        case MH_CIGAM_64:
            return (uintptr_t)(((struct mach_header_64*)header) + 1);
        default:
            // Header is corrupt
            return 0;
    }
}
