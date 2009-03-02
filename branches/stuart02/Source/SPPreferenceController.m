//
//  SPPreferenceController.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on Dec 10, 2008
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//
//  More info at <http://code.google.com/p/sequel-pro/>

#import "SPPreferenceController.h"
#import "SPWindowAdditions.h"
#import "SPFavoriteTextFieldCell.h"
#import "KeyChain.h"

#define FAVORITES_PB_DRAG_TYPE @"SequelProPreferencesPasteboard"

#define PREFERENCE_TOOLBAR_GENERAL       @"Preference Toolbar General"
#define PREFERENCE_TOOLBAR_TABLES        @"Preference Toolbar Tables"
#define PREFERENCE_TOOLBAR_FAVORITES     @"Preference Toolbar Favorites"
#define PREFERENCE_TOOLBAR_NOTIFICATIONS @"Preference Toolbar Notifications"
#define PREFERENCE_TOOLBAR_ADVANCED      @"Preference Toolbar Advanced"

@interface SPPreferenceController (PrivateAPI)

- (void)_setupToolbar;
- (void)_resizeWindowForContentView:(NSView *)view;

@end

@implementation SPPreferenceController

// -------------------------------------------------------------------------------
// init
// -------------------------------------------------------------------------------
- (id)init
{
	return [super initWithWindowNibName:@"Preferences"];
}

// -------------------------------------------------------------------------------
// windowDidLoad
// -------------------------------------------------------------------------------
- (void)windowDidLoad
{	
	[self _setupToolbar];
	
	prefs    = [NSUserDefaults standardUserDefaults];
	keychain = [[KeyChain alloc] init];
	
	favorites = [[NSMutableArray alloc] initWithArray:[prefs objectForKey:@"favorites"]];
	
	if (favorites == nil) {
		favorites = [NSMutableArray array];
	}
	
	SPFavoriteTextFieldCell *tableCell = [[[SPFavoriteTextFieldCell alloc] init] autorelease];
	
	[tableCell setImage:[NSImage imageNamed:@"database"]];
	
	// Replace column's NSTextFieldCell with custom SWProfileTextFieldCell
	[[[favoritesTableView tableColumns] objectAtIndex:0] setDataCell:tableCell];
	
	[favoritesTableView registerForDraggedTypes:[NSArray arrayWithObject:FAVORITES_PB_DRAG_TYPE]];
	
	[favoritesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	[favoritesTableView reloadData];
}

#pragma mark -
#pragma mark IBAction methods

// -------------------------------------------------------------------------------
// addFavorite:
// -------------------------------------------------------------------------------
- (IBAction)addFavorite:(id)sender
{
	// Create default favorite
	NSMutableDictionary *favorite = [NSMutableDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"New Favorite", @"", @"", @"", @"", @"", nil]
																		  forKeys:[NSArray arrayWithObjects:@"name", @"host", @"socket", @"user", @"port", @"database", nil]];
	
	[favorites addObject:favorite];
	[favoritesController addObject:favorite];
	
	[favoritesTableView reloadData];
}

// -------------------------------------------------------------------------------
// removeFavorite:
// -------------------------------------------------------------------------------
- (IBAction)removeFavorite:(id)sender
{
	if ([favoritesTableView numberOfSelectedRows] == 1) {
		
		// Get selected favorite's details
		NSString *name     = [[favorites objectAtIndex:[favoritesTableView selectedRow]] objectForKey:@"name"];
		NSString *user     = [[favorites objectAtIndex:[favoritesTableView selectedRow]] objectForKey:@"user"];
		NSString *host     = [[favorites objectAtIndex:[favoritesTableView selectedRow]] objectForKey:@"host"];
		NSString *database = [[favorites objectAtIndex:[favoritesTableView selectedRow]] objectForKey:@"database"];
		
		// Remove passwords from the Keychain
		[keychain deletePasswordForName:[NSString stringWithFormat:@"Sequel Pro : %@", name]
								account:[NSString stringWithFormat:@"%@@%@/%@", user, host, database]];
		[keychain deletePasswordForName:[NSString stringWithFormat:@"Sequel Pro SSHTunnel : %@", name]
								account:[NSString stringWithFormat:@"%@@%@/%@", user, host, database]];
		
		[favorites removeObjectAtIndex:[favoritesTableView selectedRow]];
		[favoritesTableView reloadData];
	}
}

// -------------------------------------------------------------------------------
// duplicateFavorite:
// -------------------------------------------------------------------------------
- (IBAction)duplicateFavorite:(id)sender
{
	if ([favoritesTableView numberOfSelectedRows] == 1) {
		
		NSMutableDictionary *favorite = [NSMutableDictionary dictionaryWithDictionary:[favorites objectAtIndex:[favoritesTableView selectedRow]]];
		
		[favorites addObject:favorite];
		[favoritesController addObject:favorite];
		
		[favoritesTableView reloadData];
	}
}

#pragma mark -
#pragma mark Toolbar item IBAction methods

// -------------------------------------------------------------------------------
// displayGeneralPreferences:
// -------------------------------------------------------------------------------
- (IBAction)displayGeneralPreferences:(id)sender
{
	[self _resizeWindowForContentView:generalView];
}

// -------------------------------------------------------------------------------
// displayTablePreferences:
// -------------------------------------------------------------------------------
- (IBAction)displayTablePreferences:(id)sender
{
	[self _resizeWindowForContentView:tablesView];
}

// -------------------------------------------------------------------------------
// displayFavoritePreferences:
// -------------------------------------------------------------------------------
- (IBAction)displayFavoritePreferences:(id)sender
{
	[self _resizeWindowForContentView:favoritesView];
}

// -------------------------------------------------------------------------------
// displayNotificationPreferences:
// -------------------------------------------------------------------------------
- (IBAction)displayNotificationPreferences:(id)sender
{
	[self _resizeWindowForContentView:notificationsView];
}

// -------------------------------------------------------------------------------
// displayAdvancedPreferences:
// -------------------------------------------------------------------------------
- (IBAction)displayAdvancedPreferences:(id)sender
{
	[self _resizeWindowForContentView:advancedView];
}

// -------------------------------------------------------------------------------
// favorites
// -------------------------------------------------------------------------------
- (NSMutableArray *)favorites
{
	return favorites;
}

#pragma mark -
#pragma mark TableView datasource methods

// -------------------------------------------------------------------------------
// numberOfRowsInTableView:
// -------------------------------------------------------------------------------
- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return [favorites count];
}

// -------------------------------------------------------------------------------
// tableView:objectValueForTableColumn:row:
// -------------------------------------------------------------------------------
- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	return [[favorites objectAtIndex:rowIndex] objectForKey:[aTableColumn identifier]];
}

#pragma mark TableView drag & drop datasource methods

// -------------------------------------------------------------------------------
// tableView:writeRows:toPasteboard:
// -------------------------------------------------------------------------------
- (BOOL)tableView:(NSTableView *)tv writeRows:(NSArray *)rows toPasteboard:(NSPasteboard *)pboard
{
	int originalRow;
	NSArray *pboardTypes;
	
	if ([rows count] == 1) {
		pboardTypes = [NSArray arrayWithObject:FAVORITES_PB_DRAG_TYPE];
		originalRow = [[rows objectAtIndex:0] intValue];
		
		[pboard declareTypes:pboardTypes owner:nil];
		[pboard setString:[[NSNumber numberWithInt:originalRow] stringValue] forType:FAVORITES_PB_DRAG_TYPE];
		
		return YES;
	} 
	else {		
		return NO;
	}
}

// -------------------------------------------------------------------------------
// tableView:validateDrop:proposedRow:proposedDropOperation:
// -------------------------------------------------------------------------------
- (NSDragOperation)tableView:(NSTableView *)tv validateDrop:(id <NSDraggingInfo>)info proposedRow:(int)row proposedDropOperation:(NSTableViewDropOperation)operation
{	
	int originalRow;
	NSArray *pboardTypes = [[info draggingPasteboard] types];
	
	if (([pboardTypes count] > 1) && (row != -1)) {
		if (([pboardTypes containsObject:FAVORITES_PB_DRAG_TYPE]) && (operation == NSTableViewDropAbove)) {
			originalRow = [[[info draggingPasteboard] stringForType:FAVORITES_PB_DRAG_TYPE] intValue];
						
			if ((row != originalRow) && (row != (originalRow + 1))) {
				return NSDragOperationMove;
			}
		}
	}
	
	return NSDragOperationNone;
}

// -------------------------------------------------------------------------------
// tableView:acceptDrop:row:dropOperation:
// -------------------------------------------------------------------------------
- (BOOL)tableView:(NSTableView *)tv acceptDrop:(id <NSDraggingInfo>)info row:(int)row dropOperation:(NSTableViewDropOperation)operation
{	
	int originalRow;
	int destinationRow;
	NSMutableDictionary *draggedRow;
	
	originalRow = [[[info draggingPasteboard] stringForType:FAVORITES_PB_DRAG_TYPE] intValue];
	destinationRow = row;
	
	if (destinationRow > originalRow) {
		destinationRow--;
	}
	
	draggedRow = [NSMutableDictionary dictionaryWithDictionary:[favorites objectAtIndex:originalRow]];
	
	[favorites removeObjectAtIndex:originalRow];
	[favorites insertObject:draggedRow atIndex:destinationRow];
	
	[favoritesTableView reloadData];
	[favoritesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:destinationRow] byExtendingSelection:NO];
	
	return YES;
}


#pragma mark -
#pragma mark TableView delegate methods
	
// -------------------------------------------------------------------------------
// tableView:willDisplayCell:forTableColumn:row:
// -------------------------------------------------------------------------------
- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(int)index
{
	if ([cell isKindOfClass:[SPFavoriteTextFieldCell class]]) {
		[cell setFavoriteName:[[favorites objectAtIndex:index] objectForKey:@"name"]];
		[cell setFavoriteHost:[[favorites objectAtIndex:index] objectForKey:@"host"]];
	}
}

// -------------------------------------------------------------------------------
// tableViewSelectionDidChange:
// -------------------------------------------------------------------------------
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{	
	if ([[favoritesTableView selectedRowIndexes] count] > 0) {
		[favoritesController setSelectedObjects:[NSArray arrayWithObject:[favorites objectAtIndex:[[favoritesTableView selectedRowIndexes] lastIndex]]]];
	}
}

#pragma mark -
#pragma mark Toolbar delegate methods

// -------------------------------------------------------------------------------
// toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:
// -------------------------------------------------------------------------------
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{		
    if ([itemIdentifier isEqualToString:PREFERENCE_TOOLBAR_GENERAL]) {
        return generalItem;
    }
	else if ([itemIdentifier isEqualToString:PREFERENCE_TOOLBAR_TABLES]) {
		return tablesItem;
	}
	else if ([itemIdentifier isEqualToString:PREFERENCE_TOOLBAR_FAVORITES]) {
		return favoritesItem;
	}
	else if ([itemIdentifier isEqualToString:PREFERENCE_TOOLBAR_NOTIFICATIONS]) {
		return notificationsItem;
	}
	else if ([itemIdentifier isEqualToString:PREFERENCE_TOOLBAR_ADVANCED]) {
		return advancedItem;
	}
	
    return [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];
}

// -------------------------------------------------------------------------------
// toolbarAllowedItemIdentifiers:
// -------------------------------------------------------------------------------
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return [NSArray arrayWithObjects:PREFERENCE_TOOLBAR_GENERAL, PREFERENCE_TOOLBAR_TABLES, PREFERENCE_TOOLBAR_FAVORITES, PREFERENCE_TOOLBAR_NOTIFICATIONS, PREFERENCE_TOOLBAR_ADVANCED, nil];
}

// -------------------------------------------------------------------------------
// toolbarDefaultItemIdentifiers:
// -------------------------------------------------------------------------------
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return [NSArray arrayWithObjects:PREFERENCE_TOOLBAR_GENERAL, PREFERENCE_TOOLBAR_TABLES, PREFERENCE_TOOLBAR_FAVORITES, PREFERENCE_TOOLBAR_NOTIFICATIONS, PREFERENCE_TOOLBAR_ADVANCED, nil];
}

// -------------------------------------------------------------------------------
// toolbarDefaultItemIdentifiers:
// -------------------------------------------------------------------------------
- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar
{
	return [NSArray arrayWithObjects:PREFERENCE_TOOLBAR_GENERAL, PREFERENCE_TOOLBAR_TABLES, PREFERENCE_TOOLBAR_FAVORITES, PREFERENCE_TOOLBAR_NOTIFICATIONS, PREFERENCE_TOOLBAR_ADVANCED, nil];
}

// -------------------------------------------------------------------------------
// dealloc
// -------------------------------------------------------------------------------
- (void)dealloc
{
	[keychain release], keychain = nil;
	
	[super dealloc];
}

@end

@implementation SPPreferenceController (PrivateAPI)

// -------------------------------------------------------------------------------
// _setupToolbar
//
// Constructs the preferences' window toolbar.
// -------------------------------------------------------------------------------
- (void)_setupToolbar
{
	toolbar = [[[NSToolbar alloc] initWithIdentifier:@"Preference Toolbar"] autorelease];
	
	// General preferences
	generalItem = [[NSToolbarItem alloc] initWithItemIdentifier:PREFERENCE_TOOLBAR_GENERAL];
    
	[generalItem setLabel:NSLocalizedString(@"General", @"")];
    [generalItem setImage:[NSImage imageNamed:@"GeneralPreferences"]];
    [generalItem setTarget:self];
    [generalItem setAction:@selector(displayGeneralPreferences:)];
	
	// Table preferences
	tablesItem = [[NSToolbarItem alloc] initWithItemIdentifier:PREFERENCE_TOOLBAR_TABLES];
	
	[tablesItem setLabel:NSLocalizedString(@"Tables", @"")];
	[tablesItem setImage:[NSImage imageNamed:@"tables-new"]];
	[tablesItem setTarget:self];
	[tablesItem setAction:@selector(displayTablePreferences:)];
	
	// Favorite preferences
	favoritesItem = [[NSToolbarItem alloc] initWithItemIdentifier:PREFERENCE_TOOLBAR_FAVORITES];
	
	[favoritesItem setLabel:NSLocalizedString(@"Favorites", @"")];
    [favoritesItem setImage:[NSImage imageNamed:@"favorites"]];
    [favoritesItem setTarget:self];
    [favoritesItem setAction:@selector(displayFavoritePreferences:)];
	
	// Notification preferences
	notificationsItem = [[NSToolbarItem alloc] initWithItemIdentifier:PREFERENCE_TOOLBAR_NOTIFICATIONS];
	
	[notificationsItem setLabel:NSLocalizedString(@"Notifications", @"")];
    [notificationsItem setImage:[NSImage imageNamed:@"notifications"]];
    [notificationsItem setTarget:self];
    [notificationsItem setAction:@selector(displayNotificationPreferences:)];
	
	// Adavanced preferences
	advancedItem = [[NSToolbarItem alloc] initWithItemIdentifier:PREFERENCE_TOOLBAR_ADVANCED];
	
	[advancedItem setLabel:NSLocalizedString(@"Advanced", @"")];
    [advancedItem setImage:[NSImage imageNamed:@"AdvancedPreferences"]];
    [advancedItem setTarget:self];
    [advancedItem setAction:@selector(displayAdvancedPreferences:)];
    
    [toolbar setDelegate:self];
	[toolbar setSelectedItemIdentifier:PREFERENCE_TOOLBAR_GENERAL];
    
	[[self window] setToolbar:toolbar];
	[[self window] setContentView:generalView];
	[[self window] setShowsToolbarButton:NO];
}

// -------------------------------------------------------------------------------
// _resizeWindowForContentView:
//
// Resizes the window to the size of the supplied view.
// -------------------------------------------------------------------------------
- (void)_resizeWindowForContentView:(NSView *)view
{
	[[self window] setContentView:blankView];
	[[self window] resizeForContentView:view titleBarVisible:YES];
}

@end
