//
//  main.m
//  SwipeSimulator — CLI helper to post a single synthetic swipe (left or right).

#import <Foundation/Foundation.h>
#import "TouchEvents.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
#if defined(LEFT)
        TLInfoSwipeDirection dir = kTLInfoSwipeLeft;
#elif defined(RIGHT)
        TLInfoSwipeDirection dir = kTLInfoSwipeRight;
#else
        TLInfoSwipeDirection dir = kTLInfoSwipeRight;
#endif

        NSDictionary *swipeInfo1 = @{
            (__bridge id)kTLInfoKeyGestureSubtype: @(kTLInfoSubtypeSwipe),
            (__bridge id)kTLInfoKeyGesturePhase: @(1),
        };
        NSDictionary *swipeInfo2 = @{
            (__bridge id)kTLInfoKeyGestureSubtype: @(kTLInfoSubtypeSwipe),
            (__bridge id)kTLInfoKeySwipeDirection: @(dir),
            (__bridge id)kTLInfoKeyGesturePhase: @(4),
        };

        CGEventRef event1 = tl_CGEventCreateFromGesture((__bridge CFDictionaryRef)swipeInfo1, (__bridge CFArrayRef)@[]);
        CGEventRef event2 = tl_CGEventCreateFromGesture((__bridge CFDictionaryRef)swipeInfo2, (__bridge CFArrayRef)@[]);

        CGEventPost(kCGHIDEventTap, event1);
        CGEventPost(kCGHIDEventTap, event2);

        CFRelease(event1);
        CFRelease(event2);

        usleep(1000000 / 128);
    }
    return 0;
}
