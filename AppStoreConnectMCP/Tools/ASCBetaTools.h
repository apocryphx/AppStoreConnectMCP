//
//  ASCBetaTools.h
//  AppStoreConnectMCP
//

#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface ASCBetaTools : NSObject
+ (nullable NSString *)listBetaGroups:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)listGroupTesters:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)addTesterToGroup:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)removeTesterFromGroup:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)listBetaFeedback:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)getBetaFeedback:(NSDictionary *)args error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
