//
//  AppDaemonUtils.swift
//  Saily
//
//  Created by Lakr Aream on 2019/7/20.
//  Copyright © 2019 Lakr Aream. All rights reserved.
//

enum daemon_status: String {
    case ready
    case busy
    case offline
}

let LKDaemonUtils = app_daemon_utils()

class app_daemon_utils {
    
    var session = ""
    var sender_lock = false
    var initialized = false
    let object = LKCBObject()
    
    var status = daemon_status.offline
    
    // swiftlint:disable:next weak_delegate
    let ins_operation_delegate = AppOperationDelegate()
    // swiftlint:disable:next weak_delegate
    let ins_download_delegate = AppDownloadDelegate()
    
    func initializing() {
        if LKDaemonUtils.session != "" {
            fatalError("[E] LKDaemonUtils 只允许初始化一次 只允许拥有一个实例")
        }
        self.session = UUID().uuidString
        self.initialized = true
        print("[*] App_daemon_utils initialized.")
        LKRoot.queue_dispatch.async {
            self.checkDaemonOnline { (ret) in
                print("[*] 获取到 Dameon 状态： " + ret.rawValue)
                self.status = ret
                
                if self.status == .ready && LKRoot.firstOpen {
                    self.daemon_msg_pass(msg: "init:req:restoreCheck")
                    sleep(1)
                    if FileManager.default.fileExists(atPath: LKRoot.root_path! + "/daemon.call/shouldRestore") {
                        DispatchQueue.main.async {
                            let alert = UIAlertController(title: "恢复".localized(), message: "我们检测到系统重置了我们的存档目录，将尝试执行恢复。".localized(), preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "取消".localized(), style: .cancel, handler: nil))
                            alert.addAction(UIAlertAction(title: "执行".localized(), style: .default, handler: { (_) in
                                UIApplication.shared.beginIgnoringInteractionEvents()
                                IHProgressHUD.show()
                                LKRoot.queue_dispatch.async {
                                    LKRoot.root_db?.close()
                                    try? FileManager.default.removeItem(atPath: LKRoot.root_path!)
                                    try? FileManager.default.createDirectory(atPath: LKRoot.root_path!, withIntermediateDirectories: true, attributes: nil)
                                    try? FileManager.default.createDirectory(atPath: LKRoot.root_path! + "/daemon.call", withIntermediateDirectories: true, attributes: nil)
                                    self.daemon_msg_pass(msg: "init:req:restoreDocuments")
                                    while !FileManager.default.fileExists(atPath: LKRoot.root_path! + "/daemon.call/resotreCompleted") {
                                        usleep(2333)
                                    }
                                    DispatchQueue.main.async {
                                        IHProgressHUD.dismiss()
                                        let alert = UIAlertController(title: "⚠️", message: "请重启程序".localized(), preferredStyle: .alert)
                                        presentViewController(some: alert)
                                        LKRoot.should_backup_when_exit = false
                                    }
                                }
                            }))
                            presentViewController(some: alert)
                        }
                    }
                }
                
                if self.status == .ready && FileManager.default.fileExists(atPath: LKRoot.root_path! + "/ud.id") {
                    if let udid = try? String(contentsOfFile: LKRoot.root_path! + "/ud.id") {
                        if udid != "" && LKRoot.settings?.real_UDID != udid {
                            let new = DBMSettings()
                            new.real_UDID = udid
                            try? LKRoot.root_db?.update(table: common_data_handler.table_name.LKSettings.rawValue, on: [DBMSettings.Properties.real_UDID], with: new)
                            LKRoot.settings?.real_UDID = udid
                            DispatchQueue.main.async {
                                let home = (LKRoot.tabbar_view_controller as? UIEnteryS)?.home
                                for view in home?.view.subviews ?? [] {
                                    view.removeFromSuperview()
                                }
                                home?.container = nil
                                home?.viewDidLoad()
                            }
                        }
                    }
                }
            }
        }
    }
    
    func requestBackup() -> operation_result {
        if status != .ready {
            LKDaemonUtils.checkDaemonOnline { (ret) in
                self.status = ret
            }
            return .failed
        }
        daemon_msg_pass(msg: "init:req:backupDocuments")
        return .success
    }
    
    func daemon_msg_pass(msg: String) {
        if sender_lock == true {
            print("[-] [-] [-] [-] [-] [-] [-] [-] [-] [-] [-] [-] [-] [-] [-] [-] [-]")
            print("[-] [-] [-] [-] [-] 发送器已上锁请检查线程安全!! [-] [-] [-] [-] [-] [-]")
            print("[-] [-] [-] [-] [-] [-] [-] [-] [-] [-] [-] [-] [-] [-] [-] [-] [-]")
            presentSwiftMessageError(title: "未知错误".localized(), body: "向权限经理发送消息失败".localized())
            LKRoot.breakPoint()
            return
        }
        sender_lock = true
        object.call_to_daemon_(with: "com.Lakr233.Saily.MsgPass.read.Begin")
        usleep(2333)
        let charasets = msg.charactersArray
        for item in charasets {
            let cs = String(item)
            let str = "com.Lakr233.Saily.MsgPass.read." + cs
            object.call_to_daemon_(with: str)
            usleep(2333)
        }
        object.call_to_daemon_(with: "com.Lakr233.Saily.MsgPass.read.End")
        usleep(2333)
        print("[*] 向远端发送数据完成：" + msg)
        sender_lock = false
    }
    
    func checkDaemonOnline(_ complete: @escaping (daemon_status) -> Void) {
        try? FileManager.default.removeItem(atPath: LKRoot.root_path! + "/daemon.call/status.txt")
        try? "".write(toFile: LKRoot.root_path! + "/daemon.call/status.txt", atomically: true, encoding: .utf8)
        LKRoot.queue_dispatch.async {
            self.daemon_msg_pass(msg: "init:path:" + LKRoot.root_path!)
            usleep(2333)
            self.daemon_msg_pass(msg: "init:status:required_call_back")
            var cnt = 0
            while cnt < 666 {
                usleep(2333)
                if FileManager.default.fileExists(atPath: LKRoot.root_path! + "/daemon.call/status.txt") {
                    if let str_read = try? String(contentsOfFile: LKRoot.root_path! + "/daemon.call/status.txt") {
                        switch str_read {
                        case "ready\n": complete(daemon_status.ready); return
                        case "rootless\n":
                            presentSwiftMessageSuccess(title: "侦测到Rootless越狱".localized(), body: "插件依赖的安装可能会出现问题，请在安装前仔细检查。".localized())
                            LKRoot.isRootLess = true
                            complete(daemon_status.ready)
                            return
                        case "busy\n": complete(daemon_status.busy); return
                        default:
                            cnt += 1
                        }
                    }
                }
                cnt += 1
            }
            complete(daemon_status.offline)
        }
    }
    
    func submit() -> (operation_result, String) {
        
        // 再次检查表单 <- 晚点再写吧我对我自己粗查代码还是很自信的
        ins_operation_delegate.printStatus()
        
        if LKRoot.isRootLess {
            print("[*] RootLess init...")
            try? FileManager.default.removeItem(atPath: LKRoot.root_path! + "/daemon.call/out.txt")
            try? "RootLess Installer - @Lakr233".write(toFile: LKRoot.root_path! + "/daemon.call/out.txt", atomically: true, encoding: .utf8)
            DispatchQueue.main.async {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    presentSwiftMessageController(some: LKDaemonMonitor(), interActinoEnabled: false)
                }
                LKRoot.queue_dispatch.asyncAfter(deadline: .now() + 1) {
                    self.rootlessSubmit()
                }
            }
        } else {
            
            var auto_install = [String]()
            var required_install = [String]()
            var required_reinstall = [String]()
            var required_remove = [String]()
            
            for item in ins_operation_delegate.operation_queue {
                var thisSection = ""
                switch item.operation_type {
                case .required_install, .required_reinstall:
                    // 拷贝安装资源
                    if let path = item.dowload?.path {
                        if FileManager.default.fileExists(atPath: path) {
                            let target = LKRoot.root_path! + "/daemon.call/debs/" + UUID().uuidString + ".deb"
                            try? FileManager.default.copyItem(atPath: path, toPath: target)
                            thisSection = "dpkg -i " + target
                            if item.operation_type == .required_install {
                                required_install.append(thisSection)
                            } else {
                                required_reinstall.append(thisSection)
                            }
                        } else {
                            return (.failed, item.package.id)
                        }
                    } else {
                        return (.failed, item.package.id)
                    }
                case .required_remove:
                    required_remove.append("dpkg --purge " + item.package.id)
                case .required_config:
                    print("required_config")
                case .required_modify_dcrp:
                    print("required_modify_dcrp")
                case .auto_install:
                    // 拷贝安装资源
                    if let path = item.dowload?.path {
                        if FileManager.default.fileExists(atPath: path) {
                            let target = LKRoot.root_path! + "/daemon.call/debs/" + UUID().uuidString + ".deb"
                            try? FileManager.default.copyItem(atPath: path, toPath: target)
                            thisSection = "dpkg -i " + target
                            auto_install.append(thisSection)
                        } else {
                            return (.failed, item.package.id)
                        }
                    } else {
                        return (.failed, item.package.id)
                    }
                case .DNG_auto_remove:
                    print("apt autoremove")
                case .unknown:
                    print("unknown")
                }
            }
            
            var script = ""
            for item in auto_install + required_reinstall + required_install + required_remove {
                script += item + " &>> " + LKRoot.root_path! + "/daemon.call/out.txt ;\n"
            }
            
            script += "dpkg --configure -a &>> " + LKRoot.root_path! + "/daemon.call/out.txt ;\n"
            script += "echo Saily::internal_session_finished::Signal &>> " + LKRoot.root_path! + "/daemon.call/out.txt ;\n"
            
            try? script.write(toFile: LKRoot.root_path! + "/daemon.call/requestScript.txt", atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: LKRoot.root_path! + "/daemon.call/out.txt")
            try? "".write(toFile: LKRoot.root_path! + "/daemon.call/out.txt", atomically: true, encoding: .utf8)
            
            print("---- Script ----")
            print("")
            print(script)
            print("---- ------ ----")
            
            
            daemon_msg_pass(msg: "init:req:fromScript")
            
            if status != .ready {
                LKRoot.queue_dispatch.async {
                    self.checkDaemonOnline { (ret) in
                        print("[*] 获取到 Dameon 状态： " + ret.rawValue)
                        self.status = ret
                    }
                }
                return (.failed, "Saily.Daemon")
            }
            
            // 打开监视窗口
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                presentSwiftMessageController(some: LKDaemonMonitor(), interActinoEnabled: false)
            }
        }
        
        return (.success, "")
    }
    
    func appendLogToFile(log: String) {
        if var read = try? String(contentsOfFile: LKRoot.root_path! + "/daemon.call/out.txt") {
            read += "\n"
            read += log
            try? read.write(toFile: LKRoot.root_path! + "/daemon.call/out.txt", atomically: true, encoding: .utf8)
        } else {
            try? log.write(toFile: LKRoot.root_path! + "/daemon.call/out.txt", atomically: true, encoding: .utf8)
        }
    }
    
    func rootlessSubmit() {
        
        appendLogToFile(log: "\nPreparing submit...")
        
        // 创建安装队列
        var rootLessQueue_Install = [String : String]()
        var rootLessQueue_unInstall = [String : [String]]()
        
        try? FileManager.default.removeItem(atPath: LKRoot.root_path! + "/daemon.call/pendingExtract")
        try? FileManager.default.createDirectory(atPath: LKRoot.root_path! + "/daemon.call/pendingExtract", withIntermediateDirectories: true, attributes: nil)
        
        for item in ins_operation_delegate.operation_queue {
            switch item.operation_type {
            case .required_install, .required_reinstall, .auto_install:
                // 拷贝安装资源
                if let path = item.dowload?.path {
                    let to = LKRoot.root_path! + "/daemon.call/pendingExtract" + "/" + item.package.id + ".deb"
                    try? FileManager.default.copyItem(atPath: path, toPath: to)
                    rootLessQueue_Install[item.package.id] = to
                    appendLogToFile(log: "Copying to " + to)
                } else {
                    print("[?] if let path = item.dowload?.path")
                }
            case .required_remove:
                // 获取文件列表
                let id = item.package.id
            default:
                print("[?] 这里有一个不被rootless支持的操作")
            }
        }
        
        // 已经把数据准备好了 等待dpkg开始解压
        appendLogToFile(log: "\nSubmit extract...")
        LKDaemonUtils.daemon_msg_pass(msg: "init:req:extractDEB")
        while !FileManager.default.fileExists(atPath: LKRoot.root_path! + "/daemon.call/pendingExtract/Done") {
            usleep(233333)
        }
        sleep(1) // Fix Permission
        try? FileManager.default.removeItem(atPath: LKRoot.root_path! + "/daemon.call/pendingExtract/Done")
        appendLogToFile(log: "Daemon returned!")
        appendLogToFile(log: (try? String(contentsOfFile: LKRoot.root_path! + "/daemon.call/pendingExtract/Done")) ?? "")
        
        // 解压完成 等待修正
        try? FileManager.default.moveItem(atPath: LKRoot.root_path! + "/daemon.call/pendingExtract", toPath: LKRoot.root_path! + "/daemon.call/pendingPatch")
        appendLogToFile(log: "\nCreating patch scripts...")
        // 我管你🐎的全部屁吃！
        let fixListAll = (LKRoot.root_path! + "/daemon.call/pendingPatch").readAllFiles()
        var script0 = """
#!/var/containers/Bundle/iosbinpack64/bin/bash

export LANG=C
export LC_CTYPE=C
export LC_ALL=C

# -->_<--

"""
        for item in fixListAll {
            // Patch -> ldid2 -> inject
            let name: String = item.split(separator: "/").last?.to_String() ?? "something???"
            script0 += "# --- " + name + " \n"
            script0 += "echo 'Fixing " + name + " ---> ' >> " + LKRoot.root_path! + "/daemon.call/out.txt" + "\n"
            script0 += "/var/containers/Bundle/iosbinpack64/usr/bin/sed -i \"\" 's/\\/Library\\//\\/var\\/LIB\\//g' " + item + "\n"
            script0 += "/var/containers/Bundle/iosbinpack64/usr/bin/sed -i \"\" 's/\\/System\\/var\\/LIB\\//\\/System\\/Library\\//g' " + item + "\n"
            script0 += "/var/containers/Bundle/iosbinpack64/usr/bin/sed -i \"\" 's/%@\\/var\\/LIB\\//%@\\/Library\\//g' " + item + "\n"
            script0 += "/var/containers/Bundle/iosbinpack64/usr/bin/sed -i \"\" 's/mobile\\/var\\/LIB\\//mobile\\/Library\\//g' " + item + "\n"
            script0 += "/var/containers/Bundle/iosbinpack64/usr/bin/sed -i \"\" 's/\\/usr\\/lib\\/libsubstrate/\\/var\\/ulb\\/libsubstrate/g' " + item + "\n"
            script0 += "/var/containers/Bundle/iosbinpack64/usr/bin/sed -i \"\" 's/\\/usr\\/lib\\/libsubstitute/\\/var\\/ulb\\/libsubstitute/g' " + item + "\n"
            script0 += "/var/containers/Bundle/iosbinpack64/usr/bin/sed -i \"\" 's/\\/usr\\/lib\\/libprefs/\\/var\\/ulb\\/libprefs/g' " + item + "\n"
            script0 += "/var/containers/Bundle/iosbinpack64/bin/ldid2 -S " + item + "\n"
            script0 += "/var/containers/Bundle/iosbinpack64/usr/bin/inject " + item + "\n"
            script0 += "# --------- \n\n"
        }
        
        try? script0.write(toFile: LKRoot.root_path! + "/daemon.call/pendingPatch/LKRTLPatchScript.sh", atomically: true, encoding: .utf8)

        appendLogToFile(log: "\nSubmiting patches...")
        LKDaemonUtils.daemon_msg_pass(msg: "init:req:rtlPatch")
        while !FileManager.default.fileExists(atPath: LKRoot.root_path! + "/daemon.call/pendingPatch/Done") {
            usleep(233333)
        }
        sleep(1) // Fix Permission
        try? FileManager.default.removeItem(atPath: LKRoot.root_path! + "/daemon.call/pendingPatch/Done")
        appendLogToFile(log: "Daemon returned!")
        appendLogToFile(log: (try? String(contentsOfFile: LKRoot.root_path! + "/daemon.call/pendingPatch/Done")) ?? "")
        
        // 记录软件包的文件
        var script_install = ""
        
        try? FileManager.default.moveItem(atPath: LKRoot.root_path! + "/daemon.call/pendingPatch", toPath: LKRoot.root_path! + "/daemon.call/pendingTrace")
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: LKRoot.root_path! + "/daemon.call/pendingTrace") {
            for object in contents {
                let name = object.dropLast(4).to_String()
                appendLogToFile(log: "\nTracing installation on " + name)
                let dbRecord = DMRTLInstallTrace()
                dbRecord.id = name
                dbRecord.list = [String]()
                let trace = (LKRoot.root_path! + "/daemon.call/pendingTrace/" + object).readAllFiles()
                let cnt = (LKRoot.root_path! + "/daemon.call/pendingTrace/" + object).count
                for longlongfile in trace {
                    let notabspath = longlongfile.dropFirst(cnt).to_String()
                    dbRecord.list?.append(notabspath)
                }
                let currentDateTime = Date()
                let formatter = DateFormatter()
                formatter.timeStyle = .medium
                formatter.dateStyle = .long
                dbRecord.time = formatter.string(from: currentDateTime) // October 8, 2016 at 10:48:53 PM
                try? LKRoot.rtlTrace_db?.insert(objects: dbRecord, intoTable: common_data_handler.table_name.LKRootLessInstalledTrace.rawValue)
            }
        } else {
            print("[?] pendingTrace ??????")
        }
        
        appendLogToFile(log: "\n<---Start-Install-->\n")
        // 修正完成 提交安装？
        
            
        
            // 卸载迭代器
        
                // 提交删除脚本
        
                // 更新数据库
        
            // 安装迭代器
        
                // 软件包迭代器
        
                    // 拷贝安装资源
        
                    // 解压安装资源
        
                    // 修正安装资源
        
                    // 记录安装资源
        
                // 合并安装文件
        
                // 合并安装资源文件记录
        
                // 更新数据库
        
                // 提交安装
        
    }
    
}
