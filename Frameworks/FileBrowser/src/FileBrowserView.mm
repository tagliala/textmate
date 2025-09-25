#import "FileBrowserView.h"
#import "FileBrowserOutlineView.h"
#import "OFB/OFBHeaderView.h"
#import "OFB/OFBActionsView.h"
#import <OakAppKit/OakUIConstructionFunctions.h>

@interface FileBrowserView () <NSAccessibilityGroup>
@property (nonatomic) NSScrollView* scrollView;
@end

@implementation FileBrowserView
- (instancetype)initWithFrame:(NSRect)aRect
{
	if(self = [super initWithFrame:aRect])
	{
		self.accessibilityRole  = NSAccessibilityGroupRole;
		self.accessibilityLabel = @"File browser";

		_headerView    = [[OFBHeaderView alloc] initWithFrame:NSZeroRect];
		_actionsView   = [[OFBActionsView alloc] initWithFrame:NSZeroRect];

		_outlineView = [[FileBrowserOutlineView alloc] initWithFrame:NSZeroRect];
		_outlineView.accessibilityLabel       = @"Files";
		_outlineView.allowsMultipleSelection  = YES;
		_outlineView.autoresizesOutlineColumn = NO;
		_outlineView.focusRingType            = NSFocusRingTypeNone;
		_outlineView.headerView               = nil;

		if(@available(macos 11.0, *))
		{
			_outlineView.style = NSTableViewStylePlain;
			_outlineView.floatsGroupRows = NO;
		}

		[_outlineView setDraggingSourceOperationMask:NSDragOperationLink|NSDragOperationMove|NSDragOperationCopy forLocal:YES];
		[_outlineView setDraggingSourceOperationMask:NSDragOperationEvery forLocal:NO];
		[_outlineView registerForDraggedTypes:@[ NSFilenamesPboardType ]];

		NSTableColumn* tableColumn = [[NSTableColumn alloc] init];
		[_outlineView addTableColumn:tableColumn];
		[_outlineView setOutlineTableColumn:tableColumn];
		[_outlineView sizeLastColumnToFit];

		_scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
		_scrollView.borderType            = NSNoBorder;
		_scrollView.documentView          = _outlineView;
		_scrollView.hasHorizontalScroller = NO;
		_scrollView.hasVerticalScroller   = YES;
		_scrollView.autohidesScrollers    = YES;

		NSDictionary* views = @{
			@"header":  _headerView,
			@"files":   _scrollView,
			@"actions": _actionsView,
		};

		OakAddAutoLayoutViewsToSuperview(views.allValues, self);
		[_headerView removeFromSuperview];
		[self addSubview:_headerView positioned:NSWindowAbove relativeTo:nil];

		OakSetupKeyViewLoop(@[ self, _headerView, _outlineView, _actionsView ]);

		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[files(==header,==actions)]|" options:0 metrics:nil views:views]];
		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[header]-(>=0)-[actions]"     options:NSLayoutFormatAlignAllLeading metrics:nil views:views]];
		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[files][actions]|"            options:NSLayoutFormatAlignAllLeading metrics:nil views:views]];

		NSEdgeInsets insets = _scrollView.contentInsets;
		insets.top += _headerView.fittingSize.height;
		_scrollView.automaticallyAdjustsContentInsets = NO;
		_scrollView.contentInsets = insets;

		// Set up appearance-aware background colors
		[self updateAppearance];
	}
	return self;
}

- (void)updateAppearance
{
	// Set a default background color that works with system appearance
	// This will be overridden by setBackgroundColor: when themes are available
	if(@available(macOS 10.14, *))
	{
		// Use semantic system colors that adapt to appearance
		_scrollView.backgroundColor = [NSColor.controlBackgroundColor colorWithAlphaComponent:1.0];
		_outlineView.backgroundColor = NSColor.clearColor;
		_scrollView.drawsBackground = YES;
	}
	else
	{
		// Fallback for older macOS versions
		_scrollView.backgroundColor = NSColor.controlBackgroundColor;
		_outlineView.backgroundColor = NSColor.clearColor;
		_scrollView.drawsBackground = YES;
	}
}

- (void)setBackgroundColor:(NSColor*)backgroundColor
{
	_scrollView.backgroundColor = backgroundColor;
	_outlineView.backgroundColor = NSColor.clearColor;
	_scrollView.drawsBackground = YES;
}
}
@end
