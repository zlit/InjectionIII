//
//  InjectionClient.mm
//  InjectionBundle
//
//  Created by John Holdsworth on 06/11/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

#import "InjectionClient.h"
#import "InjectionServer.h"

#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
#if __has_include("tvOSInjection-Swift.h")
#import "tvOSInjection-Swift.h"
#else
#import "iOSInjection-Swift.h"
#endif
#else
#import "macOSInjection-Swift.h"
#endif


@implementation InjectionClient

+ (void)load {
    // connect to InjetionIII.app using sicket
    printf("InjectionClient is loading.\n");
    if (InjectionClient *client = [self connectTo:INJECTION_ADDRESS])
        [client run];
    else
        printf("Injection loaded but could not connect. Is InjectionIII.app running?\n");

}

- (void)runInBackground {
    [self writeString:[NSBundle mainBundle].privateFrameworksPath];
    
    NSString *projectFile = [self readString];
    printf("Injection connected, watching %s/...\n",
           projectFile.stringByDeletingLastPathComponent.UTF8String);
    
#ifdef __LP64__
    [self writeString:@"x86_64"];
#else
    [self writeString:@"i386"];
#endif
    [self writeString:[NSBundle mainBundle].executablePath];

    [SwiftEval sharedInstance].projectFile = projectFile;
    [SwiftEval sharedInstance].injectionNumber = 100;

    int codesignStatusPipe[2];
    pipe(codesignStatusPipe);
    SimpleSocket *reader = [[SimpleSocket alloc] initSocket:codesignStatusPipe[0]];
    SimpleSocket *writer = [[SimpleSocket alloc] initSocket:codesignStatusPipe[1]];

    // make available implementation of signing delegated to macOS app
    [SwiftEval sharedInstance].signer = ^BOOL(NSString *_Nonnull dylib) {
        [self writeString:dylib];
        return [reader readString].boolValue;
    };

    // As tmp file names come in, inject them
    while (NSString *swiftSource = [self readString])
        if ([swiftSource hasPrefix:@"LOG "])
            printf("%s\n", [swiftSource substringFromIndex:@"LOG ".length].UTF8String);
        else if ([swiftSource hasPrefix:@"SIGNED "])
            [writer writeString:[swiftSource substringFromIndex:@"SIGNED ".length]];
        else if ([swiftSource hasPrefix:@"THEME "]){
            NSString *themeContent = [swiftSource substringFromIndex:@"SIGNED ".length];
            if([themeContent containsString:@"swift_lzl"]){
                NSArray *splitArray = [themeContent componentsSeparatedByString:@"swift_lzl"];
                if ([splitArray count] == 2) {
                    NSString *fileName = [splitArray firstObject];
                    NSString *content = [splitArray lastObject];
                    NSString *type = [fileName pathExtension];
                    NSString *filePath = [fileName stringByReplacingOccurrencesOfString:[@"." stringByAppendingString:type ] withString:@""];
                    NSString *themePath = [[NSBundle mainBundle] pathForResource:filePath
                                                                          ofType:type];
                    NSLog(@"%@",themePath);
                    NSError *error;
                    [content writeToFile:themePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
                    if (error) {
                        NSLog(@"%@",error);
                    }
                    NSLog(@"replace theme down");
                    
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"ZLTHEMEINJECT"
                                                                        object:nil];
                }
            }
        }
        else
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *err;
                if ([swiftSource hasPrefix:@"INJECT "])
                    [SwiftInjection injectWithTmpfile:[swiftSource substringFromIndex:@"INJECT ".length] error:&err];
                [self writeString:err ? [@"ERROR " stringByAppendingString:err.localizedDescription] : @"COMPLETE"];
            });
}

@end
