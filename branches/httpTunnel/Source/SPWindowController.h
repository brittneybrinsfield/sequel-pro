//
//  $Id: SPWindowController.h 3745 2012-07-25 10:18:02Z stuart02 $
//
//  SPWindowController.h
//  sequel-pro
//
//  Created by Rowan Beentje on May 16, 2010.
//  Copyright (c) 2010 Rowan Beentje. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <http://code.google.com/p/sequel-pro/>

@class PSMTabBarControl;
@class SPDatabaseDocument;

@interface SPWindowController : NSWindowController
{
	IBOutlet PSMTabBarControl *tabBar;
	IBOutlet NSTabView *tabView;
	
	NSMenuItem *closeWindowMenuItem;
	NSMenuItem *closeTabMenuItem;

	NSMutableArray *managedDatabaseConnections;
	SPDatabaseDocument *selectedTableDocument;
}

// Database connection management
- (IBAction)addNewConnection:(id)sender;
- (IBAction)moveSelectedTabInNewWindow:(id)sender;
- (SPDatabaseDocument *)selectedTableDocument;
- (void)updateSelectedTableDocument;
- (void)updateAllTabTitles:(id)sender;
- (IBAction)closeTab:(id)sender;
- (IBAction)selectNextDocumentTab:(id)sender;
- (IBAction)selectPreviousDocumentTab:(id)sender;
- (IBAction)toggleTabBarShown:(id)sender;
- (NSArray *)documents;
- (void)selectTabAtIndex:(NSInteger)index;
- (void)setHideForSingleTab:(BOOL)hide;

@end