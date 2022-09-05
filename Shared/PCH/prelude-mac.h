#ifndef PRELUDE_MAC_H_X1SR1JB2
#define PRELUDE_MAC_H_X1SR1JB2

#import "prelude.c"

#import <AudioToolbox/AudioToolbox.h>
#import <Carbon/Carbon.h>
#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreServices/CoreServices.h>
#import <CoreText/CoreText.h>
#import <Security/Security.h>
#import <ServiceManagement/ServiceManagement.h>
#import <SystemConfiguration/SystemConfiguration.h>

#import <libkern/OSAtomic.h>
#import <machine/byte_order.h>

#import <os/activity.h>
#import <os/log.h>

// vfork() is deprecated in macOS 12+, with posix_spawn() and fork() as intended replacements.
// However, it's still useful to indicate where vfork() can be used on non-macOS systems,
// so rather than s/vfork/fork/g in the actual source, let the preprocessor do it.
#define vfork fork

#endif /* end of include guard: PRELUDE_MAC_H_X1SR1JB2 */
