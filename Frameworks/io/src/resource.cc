#include "resource.h"
#include "path.h"
#include <cf/cf.h>
#include <CoreServices/CoreServices.h>

namespace path
{
	bool is_text_clipping (std::string const& path)
	{
		bool res = false;
		if(extension(path) == "textClipping")
		{
			res = true;
		}
		else if(CFURLRef url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (UInt8 const*)path.data(), path.size(), false))
		{
			CFStringRef contentType = nullptr;
			if (CFURLCopyResourcePropertyForKey(url, kCFURLContentTypeKey, &contentType, nullptr) && contentType) {
				// Check if the content type conforms to text clipping
				// Modern approach using UTType instead of deprecated Launch Services
				res = UTTypeConformsTo(contentType, CFSTR("com.apple.text-clipping"));
				CFRelease(contentType);
			}
			CFRelease(url);
		}
		return res;
	}

	std::string resource (std::string const& path, ResType theType, ResID theID)
	{
		std::string res = NULL_STR;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		FSRef fsref;
		if(noErr != FSPathMakeRefWithOptions((UInt8 const*)path.c_str(), kFSPathMakeRefDoNotFollowLeafSymlink, &fsref, NULL))
		{
			if(ResFileRefNum ref = FSOpenResFile(&fsref, fsRdPerm))
			{
				if(Handle handle = Get1Resource(theType, theID))
				{
					HLock(handle);
					res = std::string(*handle, *handle + GetHandleSize(handle));
					HUnlock(handle);
					ReleaseResource(handle);
				}
				CloseResFile(ref);
			}
		}
#pragma clang diagnostic pop
		return res;
	}

} /* path */
