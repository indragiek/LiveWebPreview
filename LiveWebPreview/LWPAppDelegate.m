//
//  LWPAppDelegate.m
//  LiveWebPreview
//
//  Created by Indragie Karunaratne on 2013-01-09.
// Copyright (c) 2013, Indragie Karunaratne. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this
// software and associated documentation files (the "Software"), to deal in the Software
// without restriction, including without limitation the rights to use, copy, modify, merge,
// publish, distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all copies
// or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
// INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
// PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
// FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#import "LWPAppDelegate.h"
#import "UKKQueue.h"
#import "WebView+LWPAdditions.h"

static NSString* const kUserDefaultsWebURLKey = @"webURL";
static NSString* const kUserDefaultsScrollPositionKey = @"scrollPosition";

@interface LWPAppDelegate ()
@property (nonatomic, strong) WebView *offscreenWebView;
@end

@implementation LWPAppDelegate {
	NSMutableSet *_loadedResources;
	NSURL *_currentURL;
	UKKQueue *_fileWatcher;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	_fileWatcher = [UKKQueue new];
	_fileWatcher.delegate = self;
	// Using a second offscreen web view for rendering
	// This makes it so that there is no blank white page when the page is reloaded
	_offscreenWebView = [[WebView alloc] initWithFrame:self.visibleWebView.frame frameName:nil groupName:nil];
	_offscreenWebView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	_offscreenWebView.shouldUpdateWhileOffscreen = YES;
	
	_offscreenWebView.frameLoadDelegate = self;
	_offscreenWebView.resourceLoadDelegate = self;
	self.visibleWebView.frameLoadDelegate = self;
	self.visibleWebView.resourceLoadDelegate = self;
	
	// Check if there's a saved URL so it can be loaded again
	NSString *URLString = [[NSUserDefaults standardUserDefaults] stringForKey:kUserDefaultsWebURLKey];
	if ([URLString length]) {
		NSURL *url = [NSURL URLWithString:URLString];
		// Check to see if the file still exists
		if ([[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
			[self loadPageWithURL:url];
		}
	}
	
	// Save the scroll state to user defaults before terminating
	[[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationWillTerminateNotification object:[NSApplication sharedApplication] queue:nil usingBlock:^(NSNotification *note) {
		NSPoint scrollPoint = self.visibleWebView.lwp_scrollView.contentView.bounds.origin;
		NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
		[ud setObject:NSStringFromPoint(scrollPoint) forKey:kUserDefaultsScrollPositionKey];
		[ud synchronize];
	}];
}

#pragma mark - Actions

- (IBAction)browse:(id)sender
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.message = @"Choose an HTML web page to load:";
	panel.allowedFileTypes = @[@"html"]; // Restrict file selection to HTML files
	panel.allowsOtherFileTypes = NO;
	[panel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result) {
		if (result == NSFileHandlingPanelOKButton) {
			NSURL *selectedURL = panel.URL;
			[self loadPageWithURL:selectedURL];
		}
	}];
}

- (void)loadPageWithURL:(NSURL *)url
{
	// Reset the path watcher when a new URL is chosen
	[_fileWatcher removeAllPaths];
	[_fileWatcher addPath:url.path];
	
	_currentURL = url;
	self.pathControl.URL = url;
	[self.visibleWebView setMainFrameURL:url.absoluteString];
	[[NSUserDefaults standardUserDefaults] setObject:url.absoluteString forKey:kUserDefaultsWebURLKey];
}

#pragma mark - WebResourceLoadDelegate

- (void)webView:(WebView *)sender resource:(id)identifier didFinishLoadingFromDataSource:(WebDataSource *)dataSource
{
	if (sender != self.visibleWebView) return;
	// This delegate method is called when each of the web resources are loaded
	// This includes stuff like images, CSS, JS files, etc.
	// Enumerate over them and add any new ones to the path watcher
	[dataSource.subresources enumerateObjectsUsingBlock:^(WebResource *resource, NSUInteger idx, BOOL *stop) {
		NSURL *resourceURL = resource.URL;
		if ([resourceURL isFileURL] && ![_loadedResources containsObject:resourceURL]) {
			[_fileWatcher addPath:resourceURL.path];
			[_loadedResources addObject:resourceURL];
		}
	}];
}

#pragma mark - WebFrameLoadDelegate

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
	if (sender == _offscreenWebView) {
		// Swap the views
		__strong WebView *oldWebView = self.visibleWebView;
		WebView *newWebView = _offscreenWebView;
		newWebView.frame = oldWebView.frame;
		
		// Synchronize the scroll positions
		NSScrollView *currentScrollView = oldWebView.lwp_scrollView;
		NSRect scrollBounds = [[currentScrollView contentView] bounds];
		[newWebView.lwp_scrollView.documentView scrollPoint:scrollBounds.origin];
		
		// Modify the view hierarchy
		[oldWebView removeFromSuperview];
		[self.window.contentView addSubview:newWebView];
		
		self.visibleWebView = newWebView;
		_offscreenWebView = oldWebView;
	} else {
		// Restore scroll position loaded from user defaults
		NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
		NSString *pointString = [ud stringForKey:kUserDefaultsScrollPositionKey];
		if (pointString) {
			NSPoint point = NSPointFromString(pointString);
			[self.visibleWebView.lwp_scrollView.documentView scrollPoint:point];
			[ud removeObjectForKey:kUserDefaultsScrollPositionKey];
		}
	}
}

#pragma mark - UKFileWatcherDelegate

- (void)watcher:(id<UKFileWatcher>)kq receivedNotification:(NSString *)nm forPath:(NSString *)fpath
{
	// Called when some file changes, we don't necessarily care which one it is
	if (!_currentURL) return;
	// This work around is necessary because some apps *delete* the HTML file before rewriting it, which causes it to be
	// automatically removed from the path watcher. This ensures that its added back if it is removed.
	[_fileWatcher removePath:fpath];
	[_fileWatcher addPath:fpath];
	// Start rendering the updated web page in the offscreen web view
	[_offscreenWebView setMainFrameURL:_currentURL.absoluteString];
	[_offscreenWebView reload:nil];
}
@end
