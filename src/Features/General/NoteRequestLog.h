#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCINoteRequestLog : NSObject

+ (void)recordObject:(nullable id)object title:(NSString *)title;

+ (NSString *)contents;
+ (void)clear;

@end

NS_ASSUME_NONNULL_END
