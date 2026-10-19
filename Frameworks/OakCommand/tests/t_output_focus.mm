#import <OakCommand/OakCommand.h>
#import <Preferences/Keys.h>

static std::map<std::string, std::string> const kInvocation;
static std::map<std::string, std::string> const kRefresh = { { "TM_REFRESH", "DocumentChanged" } };

void test_output_takes_the_focus_when_a_command_is_invoked ()
{
	OAK_ASSERT(OakCommandOutputTakesFocus(kInvocation, YES));
}

void test_an_automatic_refresh_leaves_the_focus ()
{
	OAK_ASSERT(!OakCommandOutputTakesFocus(kRefresh, YES));
	OAK_ASSERT(!OakCommandOutputTakesFocus({ { "TM_REFRESH", "DocumentSaved" } }, YES));
}

void test_the_preference_turns_focus_off ()
{
	OAK_ASSERT(!OakCommandOutputTakesFocus(kInvocation, NO));
	OAK_ASSERT(!OakCommandOutputTakesFocus(kRefresh, NO));
}

void test_output_takes_the_focus_by_default ()
{
	RegisterDefaults();
	OAK_ASSERT([NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsHTMLOutputTakesFocusKey]);
}
