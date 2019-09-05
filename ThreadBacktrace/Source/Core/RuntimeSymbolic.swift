//
//  ThreadBacktrace.swift
//  ThreadBacktrace
//
//  Created by yans on 2019/9/5.
//

import Foundation
import MachO

//MARK: 动态符号表解析
/// 根据 Runtime 获取的符号表 解析符号
/// - Parameters:
///   - address: 真实地址
///   - index: 序号
///   - aslr: address 对应的 ASLR，默认为当前进程的 ASLR
func _symbolic(_ address: UInt, index: Int, aslr: Int = _appASLR) -> StackSymbol {
    
    guard let symbol = _symbolic(address, aslr: aslr) else {
        return StackSymbol(symbol: "not symbol",
                           file: "",
                           address: address,
                           symbolAddress: 0,
                           image: "dylib",
                           offset: 0,
                           index: index)
    }
    
    return StackSymbol(symbol: "[\(symbol.class) \(symbol.name)]",
                       file: "",
                       address: address,
                       symbolAddress: symbol.address,
                       image: _appImageName,
                       offset: address - UInt(aslr) - symbol.address,
                       index: index)
}

/// 从动态符号表查找符号
/// - Parameters:
///   - address: 真实地址
///   - aslr: 真实地址对应的 ASLR
private func _symbolic(_ address: UInt, aslr: Int) -> SymbolEntry? {
    let symbolTable = _appSymbolTable
    
    let baseAddress = address - UInt(aslr)
    
    guard !symbolTable.isEmpty else {
        return nil
    }
    
    // 符号表地址区间，符号表已按地址升序排序
    let addressInterval = symbolTable.first!.address ... symbolTable.last!.address
    guard addressInterval.contains(baseAddress) else {
        return nil
    }
    
    // 取满足条件的第一个符号
    return symbolTable.filter({ $0.address <= baseAddress}).last
}

//MARK: 存在符号表解析
/// 根据 Mach-O 符号表 解析符号
func _stackSymbol(_ address: UInt, index: Int) -> StackSymbol {
    var info = dl_info()
    _dladdr(address, &info)

    /*
         dladdr(UnsafeRawPointer(bitPattern: address), &info)
         可用此接口验证 dl_info 地址数据是否正确
     */

    return StackSymbol(symbol: _symbol(info: info),
                       file: _dli_fname(with: info),
                       address: address,
                       symbolAddress: unsafeBitCast(info.dli_saddr, to: UInt.self),
                       image: _image(info: info),
                       offset: _offset(info: info, address: address),
                       index: index
    )
}
/// the symbol nearest the address
private func _symbol(info: dl_info) -> String {
    if
        let dli_sname = info.dli_sname,
        let sname = String(validatingUTF8: dli_sname) {
        return sname
    }
    else if
        let dli_fname = info.dli_fname,
        let _ = String(validatingUTF8: dli_fname) {
        return _image(info: info)
    }
    else {
        return String(format: "0x%1x", UInt(bitPattern: info.dli_saddr))
    }
}

/// thanks to https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlAddressInfo.swift
/// the "image" (shared object pathname) for the instruction
private func _image(info: dl_info) -> String {
    guard
        let dli_fname = info.dli_fname,
        let fname = String(validatingUTF8: dli_fname),
        let _ = fname.range(of: "/", options: .backwards, range: nil, locale: nil)
    else {
        return "???"
    }
    
    return (fname as NSString).lastPathComponent
}

/// the address' offset relative to the nearest symbol
private func _offset(info: dl_info, address: UInt) -> UInt {
    if
        let dli_sname = info.dli_sname,
        let _ = String(validatingUTF8: dli_sname) {
        return address - UInt(bitPattern: info.dli_saddr)
    }
    else if
        let dli_fname = info.dli_fname,
        let _ = String(validatingUTF8: dli_fname) {
        return address - UInt(bitPattern: info.dli_fbase)
    }
    else {
        return address - UInt(bitPattern: info.dli_saddr)
    }
}

private func _dli_fname(with info: dl_info) -> String {
    if has_dli_fname(info) {
        return String(cString: info.dli_fname)
    }
    else {
        return "-"
    }
}

//MARK: DEMO
/// String -> CSring
func MakeCString(_ string: String) -> UnsafePointer<Int8> {
    let count = string.utf8CString.count
    let strP = UnsafeMutableBufferPointer<Int8>.allocate(capacity: count)
    strP.initialize(from: string.utf8CString)
    return UnsafePointer<Int8>(strP.baseAddress)!
}

/// 判断地址是否在 Mach-O Text 段中
func _isMachTextSegment(_ address: UInt) -> Bool {
    return true
}

//func _mach_segment() {
//    let pageZeroSegment = getsegbyname(MakeCString("__PAGEZERO")).pointee
//    let textSegment = getsegbyname(MakeCString("__TEXT")).pointee
//    let dataSegment = getsegbyname(MakeCString("__DATA")).pointee
//    let linkeditSegment = getsegbyname(MakeCString("__LINKEDIT")).pointee
//
//    let segmentList = [
//        pageZeroSegment,
//        textSegment,
//        dataSegment,
//        linkeditSegment
//    ]
//
//    let classlistSection = getsectbyname(MakeCString("__DATA"), MakeCString("__objc_classlist")).pointee
//    print("classlistSection: \(classlistSection)")
//
//    print("<----------------------------->")
//    segmentList.forEach { segment in
//        print("segment: \(segment)  address: \(segment.vmaddr)   size: \(segment.vmsize)")
//    }
//    print("<----------------------------->")
//}
