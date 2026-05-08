//
//  DaemonStartup.h
//  LemonDaemon
//

//  Copyright © 2018 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>


BOOL isNeedExitDaemon(pid_t clientPid);

void exitDaemon(void);

// Security fix: startDaemon() 已移除，socket 唤醒机制不再使用

//Lemon或monitor退出时通知Daemon，Daemon决定要不要退出自己。
int clientExit(pid_t clientPid);

void printDaemonOrAgentsStatus(void);
