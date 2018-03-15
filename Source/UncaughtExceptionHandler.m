//
//  UncaughtExceptionHandler.m
//
//  Created by dongxu 00182056 on 2018/02/06.
//  Copyright Huawei Co,.Ltd. All rights reserved.
//

#import "UncaughtExceptionHandler.h"
#include <libkern/OSAtomic.h>
#include <execinfo.h>
#import <Common_Lib/HWLog.h>
//#import "BIDataReportHelper.h"

NSString * const SignalExceptionName = @"SignalExceptionName";
NSString * const SignalExceptionKey = @"SignalExceptionKey";
NSString * const ExceptionCallStacks = @"ExceptionCallStacks";

volatile int32_t UncaughtExceptionCount = 0;
static const int32_t UncaughtExceptionMaximum = 10;

@implementation UncaughtExceptionHandler

+ (NSArray *)backtrace {
    //设置保存调用堆栈的buffer最大为128，调用backtrace用来获取当前线程的调用堆栈，获取的信息存放在这里的callstack中
    //backtrace返回值是实际获取的指针个数
    void *callstack[128];
    int frames = backtrace(callstack, 128);
    char **strs = backtrace_symbols(callstack, frames);

    NSMutableArray *backtrace = [NSMutableArray arrayWithCapacity:frames];
    for (int i = 0; i < frames; i++) {
        [backtrace addObject:[NSString stringWithUTF8String:strs[i]]];
    }
    free(strs);

    return backtrace;
}

- (void)handleException:(NSException *)exception {
    if (!exception) {
        return;
    }

    //获取崩溃信息
    NSString *name = [exception name];
    NSString *reason = [exception reason];
    NSArray *callStack = [[exception userInfo] objectForKey:ExceptionCallStacks];

    //组合崩溃信息并进行输出及保存
    NSString *exceptionInfo = @"\n=============== Exception Info ===============\n";
    exceptionInfo = [exceptionInfo stringByAppendingFormat:@"Exception Name: %@\n", name];
    exceptionInfo = [exceptionInfo stringByAppendingFormat:@"Exception Reason: %@\n", reason];
    exceptionInfo = [exceptionInfo stringByAppendingFormat:@"Exception Call Stack: %@\n", callStack];
    ERRLOG(@"%@", exceptionInfo);

    /* BEGIN PN:AR000A0EO2 Added by lwx515630 2017/12/26 */
    //获取当前日期
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd"];
    NSString *dateTime = [formatter stringFromDate:[NSDate date]];
    //拼接上传参数
    NSDictionary *BI_crash = @{BI_key_app_ver:[BIDataReportHelper getAPPVersion],
                       BI_key_phone_manufacturer:[BIDataReportHelper getPhoneManufacturer],
                       BI_key_phone_type:[BIDataReportHelper getPhoneType],
                       BI_key_phone_os_ver:[BIDataReportHelper getPhoneOSVersion],
                       BI_key_throwable_msg:callStack,
                       BI_key_throwable_stack_info:name,
                       BI_key_throwable_cause_msg:reason,
                       BI_key_crash_date:dateTime};
    //写入文件保存崩溃信息(此处使用NSUserDefaults储存失败)
    [BI_crash writeToFile:[NSString stringWithFormat:@"%@/Documents/BI_CrashError.log",NSHomeDirectory()] atomically:YES];
    /* END PN:AR000A0EO2 Added by lwx515630 2017/12/26 */
}

void HandleException(NSException *exception) {
    if (!exception) {
        return;
    }

    int32_t exceptionCount = OSAtomicIncrement32(&UncaughtExceptionCount);
    if (exceptionCount > UncaughtExceptionMaximum) {
        DEBUGLOG(@"Exception异常数超过最大异常处理数");
        return;
    }

    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:[exception userInfo]];
    [userInfo setObject:[exception callStackSymbols] forKey:ExceptionCallStacks];

    NSException *exc = [NSException exceptionWithName:[exception name]
                                               reason:[exception reason]
                                             userInfo:userInfo];

    [[[UncaughtExceptionHandler alloc] init] performSelectorOnMainThread:@selector(handleException:)
                                                              withObject: exc
                                                           waitUntilDone:YES];
}

void SignalHandler(int signal) {
    int32_t exceptionCount = OSAtomicIncrement32(&UncaughtExceptionCount);
    if (exceptionCount > UncaughtExceptionMaximum) {
        DEBUGLOG(@"Signal异常数超过最大异常处理数, signal = %d.", signal);
        exit(0);
    }

    NSString *reason = [NSString stringWithFormat:@"Signal %d was raised.", signal];

    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    [userInfo setObject:[NSNumber numberWithInt:signal] forKey:SignalExceptionKey];
	[userInfo setObject:[[UncaughtExceptionHandler backtrace] copy] forKey:ExceptionCallStacks];

    NSException *exc = [NSException exceptionWithName:SignalExceptionName
                                               reason:reason
                                             userInfo:userInfo];

    [[[UncaughtExceptionHandler alloc] init] performSelectorOnMainThread:@selector(handleException:)
                                                              withObject:exc
                                                           waitUntilDone:YES];
}

+ (void)installUncaughtExceptionHandler {
    //设置系统异常捕获函数
    NSSetUncaughtExceptionHandler(&HandleException);
    //设置Signal信息处理
    signal(SIGABRT, SignalHandler);
    signal(SIGILL, SignalHandler);
#ifdef DEBUG
    signal(SIGSEGV, SignalHandler);
#endif
    signal(SIGFPE, SignalHandler);
    signal(SIGBUS, SignalHandler);
    signal(SIGPIPE, SignalHandler);
}

@end
