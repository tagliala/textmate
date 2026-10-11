#import <SoftwareUpdate/SoftwareUpdate.h>
#import <test/jail.h>

// After the updater replaces the bundle in place, the Dock and Finder learn
// about the new version through the bundle's modification time. The helper
// has to bring that time forward whatever the extracted archive carried.
void test_modification_time_is_brought_forward ()
{
	test::jail_t jail;
	jail.mkdir("Stale.app");
	NSString* path = [NSString stringWithUTF8String:jail.path("Stale.app").c_str()];

	NSDate* anHourAgo = [NSDate dateWithTimeIntervalSinceNow:-3600];
	OAK_ASSERT([NSFileManager.defaultManager setAttributes:@{ NSFileModificationDate: anHourAgo } ofItemAtPath:path error:nil]);

	OAK_ASSERT(OakNoteReplacedBundleAtURL([NSURL fileURLWithPath:path]));

	NSDate* after = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFileModificationDate];
	OAK_ASSERT(after != nil);
	OAK_ASSERT(fabs([after timeIntervalSinceNow]) < 5.0);
}

void test_missing_bundle_is_reported ()
{
	test::jail_t jail;
	NSString* path = [NSString stringWithUTF8String:jail.path("Missing.app").c_str()];
	OAK_ASSERT(!OakNoteReplacedBundleAtURL([NSURL fileURLWithPath:path]));
}
