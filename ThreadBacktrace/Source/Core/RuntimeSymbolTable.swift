//
//  SymbolTable.swift
//  ThreadBacktrace
//
//  Created by yans on 2019/9/5.
//

import Foundation
import ObjectiveC
import MachO

/// Key 枚举
private enum Key {
    static let AppVersion : String = "CFBundleShortVersionString"
    static let CustomVersion : String = "CustomVersion"
    static let SymbolTablePath : String = ""
}

/// APP Runtiem 动态符号表（已减去 ASLR）
public private(set) var _appSymbolTable : [SymbolEntry] = []
/// ASLR
public private(set) var _appASLR : Int = 0
/// APP 镜像 Index
public private(set) var _appImageIndex : UInt32 = 0
/// APP 镜像 Name
public private(set) var _appImageName : String = ""

/// APP 自定义版本号 默认值为 CFBundleShortVersionString
private var _customAppVersion : String = {
    return Bundle.main.infoDictionary?[Key.AppVersion] as? String ?? ""
}()

/// 是否存在 runtime 获取的APP符号表
var IsAppSymbolTable : Bool {
    return !_appSymbolTable.isEmpty
}

//MARK: 符号表获取
/// 初始化符号表数据
public func InitializeSymbolTable() {
    guard #available(iOS 10.0, *) else {
        print("此 API iOS10 及以上才生效")
        return
    }
    
    // 子线程获取符号表
    Thread.detachNewThread {
        
        _appASLR = ASLR
        _appImageIndex = AppImageIndex
        _appImageName = AppImageName
        
        let localVersion = UserDefaults.standard.string(forKey: Key.CustomVersion) ?? ""
        let hasSymbolTable = FileManager.default
            .fileExists(atPath: SymbolTableURL?.absoluteString ?? "")
        
        // 版本号发生变化时才重新生成符号表
        if localVersion != _customAppVersion || !hasSymbolTable {
            // 创建符号表
            _appSymbolTable = RuntiemSymbolTable()
            // 保存符号表
            SaveSymbolTable(_appSymbolTable)
            
            UserDefaults.standard.setValue(_customAppVersion, forKey: Key.CustomVersion)
            UserDefaults.standard.synchronize()
        }
        else {
            // 从本地读取
            _appSymbolTable = ReadSymbolTable()
        }
        
        print("-------> 符号表初始化完成 symbol count: \(_appSymbolTable.count)")
    }
}

/// runtime 动态获取 APP 符号表
private func RuntiemSymbolTable() -> [SymbolEntry] {
    guard
        let imageName = _dyld_get_image_name(_appImageIndex)
    else {
        return []
    }
    
    // 获取当前 Image 所有 class
    var classCount : UInt32 = 0
    guard let classeList = objc_copyClassNamesForImage(imageName, &classCount) else {
        return []
    }
    
    // 当前运行 aslr
    let aslr = _appASLR
    
    // 符号表
    var symbloTable : [SymbolEntry] = [];
    
    for i in 0 ..< classCount {
        let className = String(cString: classeList[Int(i)])
        var methodCount : UInt32 = 0
        
        // 获取 class 所有 OC MethodList
        guard
            let methodList = class_copyMethodList(
                NSClassFromString(className),
                &methodCount
            )
        else {
            continue
        }
        
        for i in 0 ..< methodCount {
            let method = methodList[Int(i)]
            let sel = method_getName(method)
            let imp = method_getImplementation(method)
            let name = NSStringFromSelector(sel) as String
            // Mach-O符号地址 = 方法表地址(真实运行地址) - ASLR
            let address = UInt(bitPattern: imp) - UInt(aslr)
            let symbol = SymbolEntry(
                class: className,
                name: name,
                address: address
            )
            
            symbloTable.append(symbol)
        }
        
    }
    
    // 按地址 从低到高 排序
    symbloTable.sort { (entry0, entry1) -> Bool in
        entry0.address < entry1.address
    }
    
    return symbloTable
}

/// 保存符号表
private func SaveSymbolTable(_ symbols: [SymbolEntry]) {
    guard
        !symbols.isEmpty,
        let data = try? JSONEncoder().encode(symbols),
        let symbolsURL = SymbolTableURL
    else {
        return
    }
 
    let isSave = FileManager.default.fileExists(atPath: symbolsURL.absoluteString)
    if isSave {
        try? FileManager.default.removeItem(at: symbolsURL)
    }
    // 写入本地文件
    let success = FileManager.default.createFile(
        atPath: symbolsURL.absoluteString,
        contents: data,
        attributes: nil
    )
    if !success {
        print("创建文件失败")
    }
}

/// 获取符号表
private func ReadSymbolTable() -> [SymbolEntry] {
    guard
        let symbolsURL = SymbolTableURL,
        FileManager.default.fileExists(atPath: symbolsURL.absoluteString),
        let symbolsData = FileManager.default.contents(atPath: symbolsURL.absoluteString),
        let symbolTable = try? JSONDecoder().decode([SymbolEntry].self, from: symbolsData)
    else {
        return []
    }
    
    return symbolTable
}

//MARK: 私有计算属性
/// 获取当前可执行文件 Mach-O idx
private var AppImageIndex : UInt32 {
    let imageCount = _dyld_image_count()
    var image_idx : UInt32 = 0
    
    for i in 0 ..< imageCount {
        let image_header = _dyld_get_image_header(i).pointee
        if image_header.filetype == MH_EXECUTE {
            image_idx = i
            break
        }
    }
    
    return image_idx
}

private var AppImageName : String {
    guard let image_name = _dyld_get_image_name(AppImageIndex) else {
        return ""
    }
    return String(cString: image_name)
}

/// 获取运行的 ASLR
private var ASLR : Int {
    return _dyld_get_image_vmaddr_slide(AppImageIndex)
}

/// 符号表FileURL
private var SymbolTableURL: URL? {
    guard
        let documentPath = NSSearchPathForDirectoriesInDomains(
            .documentDirectory,
            .userDomainMask,
            true
        ).first
    else {
        return nil
    }
    
    let symbolsDirectory = "\(documentPath)/SymbolTable"
    guard !FileManager.default.fileExists(atPath: symbolsDirectory) else {
        return URL(string: "\(symbolsDirectory)/symbol.text")
    }
    
    do {
        try FileManager.default.createDirectory(
            atPath: symbolsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    } catch let error {
        print(error)
        return nil
    }
    
    return URL(fileURLWithPath: "\(symbolsDirectory)/symbol.text")
}

/**
 面向对象封装
 
 public class AppSymbolTable {
     
     public static let shared = AppSymbolTable()
     
     /// 当前 APP 动态创建的符号表
     private(set) var symbolTable : [SymbolEntry] = []
     
     /// 当前 APP 的 ASLR
     private(set) var aslr : Int = 0
     
     /// 当前 APP 的 ImageIndex
     private(set) var imageIndex : UInt32 = 0
     
     /// APP 自定义版本号 默认值为 CFBundleShortVersionString
     private var customAppVersion : String = {
         return Bundle.main.infoDictionary?[Key.AppVersion] as? String ?? ""
     }()
     
     private init() {
     }
     
 }

 extension AppSymbolTable {
     
     public func asyncInitialize() {
         // 子线程获取符号表
         guard #available(iOS 10.0, *) else {
             return
         }
         
         Thread.detachNewThread {
             self.initialize()
         }
     }
     
     private func initialize() {
         aslr = appASLR()
         imageIndex = appImageIndex()
         
         let symbolTablePath = symbolTableURL()?.absoluteString ?? ""
         let hasSymbolTable = FileManager.default.fileExists(atPath: symbolTablePath)
         let localVersion = UserDefaults.standard.string(forKey: Key.CustomVersion) ?? ""
         
         // 版本号发生变化时才重新生成符号表
         if localVersion != customAppVersion || !hasSymbolTable {
             // 创建符号表
             symbolTable = createSymbolTable()
             // 保存符号表
             saveSymbolTable(symbolTable)
             
             UserDefaults.standard.setValue(customAppVersion, forKey: Key.CustomVersion)
             UserDefaults.standard.synchronize()
         }
         else {
             // 从本地读取
             symbolTable = readSymbolTable()
         }
         
         print("-------> 符号表初始化完成 symbol count: \(symbolTable.count)")
     }
     
     /// 动态获取 APP Mach-O 符号表
     private func createSymbolTable() -> [SymbolEntry] {
         guard
             let imageName = _dyld_get_image_name(imageIndex)
         else {
             return []
         }
         
         // 获取当前 Image 所有 class
         var classCount : UInt32 = 0
         guard let classeList = objc_copyClassNamesForImage(imageName, &classCount) else {
             return []
         }
         
         // 符号表
         var symbloTable : [SymbolEntry] = [];
         
         for i in 0 ..< classCount {
             let className = String(cString: classeList[Int(i)])
             var methodCount : UInt32 = 0
             
             // 获取 class 所有 OC MethodList
             guard
                 let methodList = class_copyMethodList(
                     NSClassFromString(className),
                     &methodCount
                 )
             else {
                 continue
             }
             
             for i in 0 ..< methodCount {
                 let method = methodList[Int(i)]
                 let sel = method_getName(method)
                 let imp = method_getImplementation(method)
                 let name = NSStringFromSelector(sel) as String
                 // Mach-O符号地址 = 方法表地址(真实运行地址) - ASLR
                 let address = UInt(bitPattern: imp) - UInt(aslr)
                 let symbol = SymbolEntry(
                     class: className,
                     name: name,
                     address: address
                 )
                 
                 symbloTable.append(symbol)
             }
             
         }
         
         // 按地址 从低到高 排序
         symbloTable.sort { (entry0, entry1) -> Bool in
             entry0.address < entry1.address
         }
         
         return symbloTable
     }
 }

 extension AppSymbolTable {
     
     /// 当前 Mach-O idx
     private func appImageIndex() -> UInt32 {
         let imageCount = _dyld_image_count()
         var image_idx : UInt32 = 0
         
         for i in 0 ..< imageCount {
             let image_header = _dyld_get_image_header(i).pointee
             if image_header.filetype == MH_EXECUTE {
                 image_idx = i
                 break
             }
         }
         
         return image_idx
     }
     
     /// 当前 Mach-O ASLR
     private func appASLR() -> Int {
         return _dyld_get_image_vmaddr_slide(appImageIndex())
     }
     
     /// 符号表FileURL
     private func symbolTableURL() -> URL? {
         guard
             let documentPath = NSSearchPathForDirectoriesInDomains(
                 .documentDirectory,
                 .userDomainMask,
                 true
             ).first
         else {
             return nil
         }
         
         let symbolsDirectory = "\(documentPath)/SymbolTable"
         guard !FileManager.default.fileExists(atPath: symbolsDirectory) else {
             return URL(string: "\(symbolsDirectory)/symbol.text")
         }
         
         do {
             try FileManager.default.createDirectory(
                 atPath: symbolsDirectory,
                 withIntermediateDirectories: true,
                 attributes: nil
             )
         } catch let error {
             print(error)
             return nil
         }
         
         return URL(fileURLWithPath: "\(symbolsDirectory)/symbol.text")
     }
     
 }

 extension AppSymbolTable {
     
     /// 保存符号表
     private func saveSymbolTable(_ symbols: [SymbolEntry]) {
         guard
             !symbols.isEmpty,
             let data = try? JSONEncoder().encode(symbols),
             let symbolsURL = symbolTableURL()
         else {
             return
         }
      
         let isSave = FileManager.default.fileExists(atPath: symbolsURL.absoluteString)
         if isSave {
             try? FileManager.default.removeItem(at: symbolsURL)
         }
         // 写入本地文件
         let success = FileManager.default.createFile(
             atPath: symbolsURL.absoluteString,
             contents: data,
             attributes: nil
         )
         if !success {
             print("创建文件失败")
         }
     }
     
     /// 获取符号表
     private func readSymbolTable() -> [SymbolEntry] {
         guard
             let symbolsURL = symbolTableURL(),
             FileManager.default.fileExists(atPath: symbolsURL.absoluteString),
             let symbolsData = FileManager.default.contents(atPath: symbolsURL.absoluteString),
             let symbolTable = try? JSONDecoder().decode([SymbolEntry].self, from: symbolsData)
         else {
             return []
         }
         
         return symbolTable
     }
 }

 extension AppSymbolTable {
     /// Key 枚举
     private enum Key {
         static let AppVersion : String = "CFBundleShortVersionString"
         static let CustomVersion : String = "CustomVersion"
         static let SymbolTablePath : String = ""
     }
 }
 
 */
