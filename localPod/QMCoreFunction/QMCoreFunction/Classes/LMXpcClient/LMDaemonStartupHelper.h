//
//  LMDaemonStartupHelper.h
//  Lemon
//
//  
//  Copyright © 2018 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define REPORT_KEY_ACTIVATE_DAEMON_ERROR             9901
#define REPORT_KEY_ACTIVATE_DAEMON_AGAIN_ERROR       9902
#define REPORT_KEY_ACTIVATE_DAEMON_FAIL              9903

@interface LMDaemonStartupHelper : NSObject

// DEPRECATED - socket 唤醒机制已移除，以下属性不再使用
@property (nonatomic, strong) NSString *agentPath __attribute__((deprecated("socket wakeup removed")));
@property (nonatomic, strong) NSArray *arguments __attribute__((deprecated("socket wakeup removed")));
@property (nonatomic, strong) NSString *cmdPath __attribute__((deprecated("socket wakeup removed")));

+ (LMDaemonStartupHelper *)shareInstance;
/// 激活 daemon：先尝试 XPC 连接，失败则提权 load plist（可能弹密码框）
- (int) activeDaemon;
/// 等待 daemon 就绪：只重试 XPC 连接，不提权不弹密码框（安装后使用）
- (int) waitForDaemon;
- (int) notiflyDaemonClientExit;
@end

NS_ASSUME_NONNULL_END
