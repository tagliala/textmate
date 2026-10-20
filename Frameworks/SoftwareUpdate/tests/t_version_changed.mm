#import <SoftwareUpdate/SoftwareUpdate.h>

// On launch the app compares the version it recorded last time with the one
// running now, and refreshes its Dock icon when they differ. Nothing was
// left behind on a first run, and a relaunch of the same version is not an
// update; any other change counts, in either direction, since the updater
// offers downgrades too.

void test_first_run_is_not_an_update ()
{
	OAK_ASSERT(!OakVersionChangedSinceLastLaunch(nil, @"2.5.1"));
	OAK_ASSERT(!OakVersionChangedSinceLastLaunch(@"", @"2.5.1"));
}

void test_same_version_is_not_an_update ()
{
	OAK_ASSERT(!OakVersionChangedSinceLastLaunch(@"2.5.1", @"2.5.1"));
}

void test_upgrade_is_an_update ()
{
	OAK_ASSERT(OakVersionChangedSinceLastLaunch(@"2.5.0", @"2.5.1"));
}

void test_downgrade_is_an_update ()
{
	OAK_ASSERT(OakVersionChangedSinceLastLaunch(@"2.5.1", @"2.5.0"));
}

void test_unknown_current_version_is_not_an_update ()
{
	OAK_ASSERT(!OakVersionChangedSinceLastLaunch(@"2.5.0", nil));
	OAK_ASSERT(!OakVersionChangedSinceLastLaunch(@"2.5.0", @""));
}
