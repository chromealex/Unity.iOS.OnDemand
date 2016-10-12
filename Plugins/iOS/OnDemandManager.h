#pragma once

@interface OnDemandManager : NSObject

+(void) startWithCompletionHandler:(void(^)())handler;

@end
