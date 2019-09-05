//
//  ViewController.swift
//  ThreadBacktrace
//
//  Created by yans on 2019/9/5.
//

import UIKit
import ThreadBacktrace

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        funcBacktrace(5)
    }

    func funcBacktrace(_ level: Int) {
        if level == 0 {
            BacktraceOfMainThread().forEach { str in
                print(str)
            }
            return
        }
        
        funcBacktrace(level - 1)
    }

}

