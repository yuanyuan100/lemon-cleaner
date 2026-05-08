//
//  LMDaemonStartupHelper.m
//  Lemon
//
//  Created by klkgogo on 2018/12/14.
//  Copyright © 2018 Tencent. All rights reserved.
//
//  Security fix: 移除 Unix Domain Socket 唤醒机制，改用 XPC MachServices 按需启动
//

#import "LMDaemonStartupHelper.h"
#import "LMDaemonXPCProtocol.h"
#import <QMCoreFunction/McCoreFunction.h>

#define DAEMON_MACH_SERVICE_NAME @"com.tencent.LemonDaemon"
#define DAEMON_PLIST_PATH @"/Library/LaunchDaemons/com.tencent.Lemon.plist"

@implementation LMDaemonStartupHelper

+ (LMDaemonStartupHelper *)shareInstance {
    static LMDaemonStartupHelper *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    return self;
}

/// 尝试通过 XPC 连接 daemon，返回 1 成功，0 失败
- (int)tryXPCConnect {
    __block int ret = 0;
    __block BOOL replied = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSXPCConnection *connection = [[NSXPCConnection alloc]
        initWithMachServiceName:DAEMON_MACH_SERVICE_NAME options:0];
    connection.remoteObjectInterface =
        [NSXPCInterface interfaceWithProtocol:@protocol(LMDaemonXPCProtocol)];

    connection.invalidationHandler = ^{
        if (!replied) {
            replied = YES;
            ret = 0;
            dispatch_semaphore_signal(semaphore);
        }
    };

    [connection resume];

    id<LMDaemonXPCProtocol> proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        NSLog(@"%s XPC connect error: %@", __FUNCTION__, error);
        if (!replied) {
            replied = YES;
            ret = 0;
            dispatch_semaphore_signal(semaphore);
        }
    }];

    // 使用 sendDataToDaemon:withReply: 做同步验证（有 reply 回调，能确认 daemon 真正响应了）
    NSData *pingData = [@"ping" dataUsingEncoding:NSUTF8StringEncoding];
    [proxy sendDataToDaemon:pingData withReply:^(NSData *replyData) {
        NSLog(@"%s XPC daemon replied, connection verified", __FUNCTION__);
        if (!replied) {
            replied = YES;
            ret = 1;
            dispatch_semaphore_signal(semaphore);
        }
    }];

    // 等待最多 3 秒
    dispatch_semaphore_wait(semaphore,
        dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));

    if (!replied) {
        ret = 0;
    }

    [connection invalidate];
    return ret;
}

/// 使用 NSAppleScript 以 root 权限 load daemon plist（会弹密码框）
- (int)loadDaemonPlist {
    NSLog(@"%s", __FUNCTION__);

    if (![[NSFileManager defaultManager] fileExistsAtPath:DAEMON_PLIST_PATH]) {
        NSLog(@"%s plist not found: %@", __FUNCTION__, DAEMON_PLIST_PATH);
        return -1;
    }

    NSString *cmd = [NSString stringWithFormat:
        @"do shell script \"/bin/launchctl load -w %@\" with administrator privileges",
        DAEMON_PLIST_PATH];

    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:cmd];
    NSDictionary *error = nil;
    [script executeAndReturnError:&error];

    if (error) {
        NSLog(@"%s launchctl load failed: %@", __FUNCTION__, error);
        return -1;
    }

    NSLog(@"%s launchctl load success", __FUNCTION__);
    return 0;
}

- (int)activeDaemon {
    NSLog(@"%s", __FUNCTION__);

    // 第一步：尝试 XPC 连接（daemon 已在运行）
    int ret = [self tryXPCConnect];
    if (ret == 1) {
        NSLog(@"%s daemon activated via XPC on first try", __FUNCTION__);
        return ret;
    }

    // 第二步：重试 XPC（daemon 可能还在启动中）
    NSLog(@"%s first XPC failed, retrying...", __FUNCTION__);
    for (int i = 0; i < 5; i++) {
        usleep(500 * 1000);
        ret = [self tryXPCConnect];
        if (ret == 1) {
            NSLog(@"%s daemon activated via XPC on retry %d", __FUNCTION__, i + 1);
            return ret;
        }
        NSLog(@"%s XPC retry %d failed", __FUNCTION__, i + 1);
    }

    // 第三步：兜底提权 load（弹密码框，仅在 plist 未注册的极端情况）
    NSLog(@"%s all XPC retries failed, loading plist with admin privileges", __FUNCTION__);
    int loadRet = [self loadDaemonPlist];
    if (loadRet != 0) {
        NSLog(@"%s load plist failed: %d", __FUNCTION__, loadRet);
        return 0;
    }

    usleep(1000 * 1000);
    ret = [self tryXPCConnect];
    NSLog(@"%s after load plist, XPC result: %d", __FUNCTION__, ret);
    return ret;
}

- (int)waitForDaemon {
    NSLog(@"%s", __FUNCTION__);

    // 只重试 XPC 连接，不提权，不弹密码框
    // 用于安装流程完成后（daemon 已被 loadPlist 拉起，只需等它就绪）
    for (int i = 0; i < 10; i++) {
        int ret = [self tryXPCConnect];
        if (ret == 1) {
            NSLog(@"%s daemon ready on attempt %d", __FUNCTION__, i + 1);
            return ret;
        }
        NSLog(@"%s waiting for daemon, attempt %d", __FUNCTION__, i + 1);
        usleep(500 * 1000); // 500ms
    }

    NSLog(@"%s daemon not ready after 5s", __FUNCTION__);
    return 0;
}

- (int)notiflyDaemonClientExit {
    NSLog(@"%s", __FUNCTION__);
    return [[McCoreFunction shareCoreFuction] notiflyClientExit];
}

@end
