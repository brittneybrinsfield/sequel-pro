//
//  $Id$
//
//  TableSource.m
//  sequel-pro
//
//  Created by lorenz textor (lorenz@textor.ch) on Wed May 01 2002.
//  Copyright (c) 2002-2003 Lorenz Textor. All rights reserved.
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

#import "TableSource.h"
#import "TablesList.h"
#import "SPTableData.h"
#import "SPSQLParser.h"
#import "SPStringAdditions.h"
#import "SPArrayAdditions.h"


@implementation TableSource

/*
loads aTable, put it in an array, update the tableViewColumns and reload the tableView
*/
- (void)loadTable:(NSString *)aTable
{
	NSEnumerator *enumerator;
	id field;
	NSArray *extrasArray;
	NSMutableDictionary *tempDefaultValues;
	NSEnumerator *extrasEnumerator;
	id extra;
	int i;
	SPSQLParser *fieldParser;

	// Check whether a save of the current row is required.
	if ( ![self saveRowOnDeselect] ) return;

	selectedTable = aTable;
	[tableSourceView deselectAll:self];
	[indexView deselectAll:self];

	if ( isEditingRow )
		return;

	// empty variables
	[enumFields removeAllObjects];

	if ( [aTable isEqualToString:@""] || !aTable ) {
		[tableFields removeAllObjects];
		[indexes removeAllObjects];
		[tableSourceView reloadData];
		[indexView reloadData];
		[addFieldButton setEnabled:NO];
		[copyFieldButton setEnabled:NO];
		[removeFieldButton setEnabled:NO];
		[addIndexButton setEnabled:NO];
		[removeIndexButton setEnabled:NO];
		[editTableButton setEnabled:NO];

		return;
	}
	
	// Enable edit table button
	[editTableButton setEnabled:YES];

	//query started
	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryWillBePerformed" object:self];
  
	//perform queries and load results in array (each row as a dictionary)
	tableSourceResult = [[mySQLConnection queryString:[NSString stringWithFormat:@"SHOW COLUMNS FROM %@", [selectedTable backtickQuotedString]]] retain];
	
	// listFieldsFromTable is broken in the current version of the framework (no back-ticks for table name)!
	//	tableSourceResult = [[mySQLConnection listFieldsFromTable:selectedTable] retain];
	//	[tableFields setArray:[[self fetchResultAsArray:tableSourceResult] retain]];
	[tableFields setArray:[self fetchResultAsArray:tableSourceResult]];
	[tableSourceResult release];

	indexResult = [[mySQLConnection queryString:[NSString stringWithFormat:@"SHOW INDEX FROM %@", [selectedTable backtickQuotedString]]] retain];
	//	[indexes setArray:[[self fetchResultAsArray:indexResult] retain]];
	[indexes setArray:[self fetchResultAsArray:indexResult]];
	[indexResult release];
	
	//get table default values
	if ( defaultValues ) {
		[defaultValues release];
		defaultValues = nil;
	}
	
	tempDefaultValues = [NSMutableDictionary dictionary];
	for ( i = 0 ; i < [tableFields count] ; i++ ) {
		[tempDefaultValues setObject:[[tableFields objectAtIndex:i] objectForKey:@"Default"] forKey:[[tableFields objectAtIndex:i] objectForKey:@"Field"]];
	}
	defaultValues = [[NSDictionary dictionaryWithDictionary:tempDefaultValues] retain];
	
	//put field length and extras in separate key
	enumerator = [tableFields objectEnumerator];

	while ( (field = [enumerator nextObject]) ) {
		NSString *type;
		NSString *length;
		NSString *extras;

		// Set up the field parser with the type definition
		fieldParser = [[SPSQLParser alloc] initWithString:[field objectForKey:@"Type"]];

		// Pull out the field type; if no brackets are found, this returns nil - in which case simple values can be used.
		type = [fieldParser trimAndReturnStringToCharacter:'(' trimmingInclusively:YES returningInclusively:NO];
		if (!type) {
			type = [NSString stringWithString:fieldParser];
			length = @"";
			extras = @"";
		} else {

			// Pull out the length, which may include enum/set values
			length = [fieldParser trimAndReturnStringToCharacter:')' trimmingInclusively:YES returningInclusively:NO];
			if (!length) length = @"";

			// Separate any remaining extras
			extras = [NSString stringWithString:fieldParser];
			if (!extras) extras = @"";
		}

		[fieldParser release];

		// Get possible values if the field is an enum or a set
		if ([type isEqualToString:@"enum"] || [type isEqualToString:@"set"]) {
			SPSQLParser *valueParser = [[SPSQLParser alloc] initWithString:length];
			NSMutableArray *possibleValues = [[NSMutableArray alloc] initWithArray:[valueParser splitStringByCharacter:',']];
			for (i = 0; i < [possibleValues count]; i++) {
				[valueParser setString:[possibleValues objectAtIndex:i]];
				[possibleValues replaceObjectAtIndex:i withObject:[valueParser unquotedString]];
			}
			[enumFields setObject:[NSArray arrayWithArray:possibleValues] forKey:[field objectForKey:@"Field"]];
			[possibleValues release];
			[valueParser release];
		}
		
		// For timestamps check to see whether "on update CURRENT_TIMESTAMP" - not returned
		// by SHOW COLUMNS - should be set from the table data store
		if ([type isEqualToString:@"timestamp"]
			&& [[[tableDataInstance columnWithName:[field objectForKey:@"Field"]] objectForKey:@"onupdatetimestamp"] intValue])
		{
			[field setObject:@"on update CURRENT_TIMESTAMP" forKey:@"Extra"];
		}

		// scan extras for values like unsigned, zerofill, binary
		extrasArray = [extras componentsSeparatedByString:@" "];
		extrasEnumerator = [extrasArray objectEnumerator];
		
		while ( (extra = [extrasEnumerator nextObject]) ) {
			if ( [extra isEqualToString:@"unsigned"] ) {
				[field setObject:@"1" forKey:@"unsigned"];
			} else if ( [extra isEqualToString:@"zerofill"] ) {
				[field setObject:@"1" forKey:@"zerofill"];
			} else if ( [extra isEqualToString:@"binary"] ) {
				[field setObject:@"1" forKey:@"binary"];
			} else {
				if ( ![extra isEqualToString:@""] )
					NSLog(@"ERROR: unknown option in field definition: %@", extra);
			}
		}
		
		[field setObject:type forKey:@"Type"];
		[field setObject:length forKey:@"Length"];
	}
	
	// If a view is selected, disable the buttons; otherwise enable.
	BOOL editingEnabled = ([tablesListInstance tableType] == SP_TABLETYPE_TABLE);
	[addFieldButton setEnabled:editingEnabled];
	[addIndexButton setEnabled:editingEnabled];
    
    //the following three buttons will only be enabled if a row field/index is selected!
	[copyFieldButton setEnabled:NO];
	[removeFieldButton setEnabled:NO];
	[removeIndexButton setEnabled:NO];
	
	//add columns to indexedColumnsField
	[indexedColumnsField removeAllItems];
	enumerator = [tableFields objectEnumerator];
	
	while ( (field = [enumerator nextObject]) ) {
		[indexedColumnsField addItemWithObjectValue:[field objectForKey:@"Field"]];
	}
	
	if ( [tableFields count] < 10 ) {
		[indexedColumnsField setNumberOfVisibleItems:[tableFields count]];
	} else {
		[indexedColumnsField setNumberOfVisibleItems:10];
	}

	// Reset font for field and index table
	NSEnumerator *indexColumnsEnumerator = [[indexView tableColumns] objectEnumerator];
	NSEnumerator *fieldColumnsEnumerator = [[tableSourceView tableColumns] objectEnumerator];
	id indexColumn;
	id fieldColumn;
	BOOL useMonospacedFont = [prefs boolForKey:@"UseMonospacedFonts"];

	while ( (indexColumn = [indexColumnsEnumerator nextObject]) )
		if ( useMonospacedFont )
			[[indexColumn dataCell] setFont:[NSFont fontWithName:@"Monaco" size:10]];
		else 
			[[indexColumn dataCell] setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];

	while ( (fieldColumn = [fieldColumnsEnumerator nextObject]) )
		if ( useMonospacedFont )
			[[fieldColumn dataCell] setFont:[NSFont fontWithName:@"Monaco" size:[NSFont smallSystemFontSize]]];
		else
			[[fieldColumn dataCell] setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];

	[tableSourceView reloadData];
	[indexView reloadData];
	
	// display and *then* tile to force scroll bars to be in the correct position
	[[tableSourceView enclosingScrollView] display];
	[[tableSourceView enclosingScrollView] tile];
	
	// Enable 'Duplicate field' if at least one field is specified
	// if no field is selected 'Duplicate field' will copy the last field
	// Enable 'Duplicate field' only for tables!
	if([tablesListInstance tableType] == SP_TABLETYPE_TABLE)
			[copyFieldButton setEnabled:([tableSourceView numberOfRows] > 0)];
	else
		[copyFieldButton setEnabled:NO];

	//query finished
	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryHasBeenPerformed" object:self];
}

/*
reloads the table (performing a new mysql-query)
*/
- (IBAction)reloadTable:(id)sender
{
	[tableDataInstance resetColumnData];
	[tablesListInstance setStatusRequiresReload:YES];
	[self loadTable:selectedTable];
}


#pragma mark -
#pragma mark Edit methods

/**
 * Adds an empty row to the tableSource-array and goes into edit mode
 */
- (IBAction)addField:(id)sender
{
	// Check whether a save of the current row is required.
	if ( ![self saveRowOnDeselect] ) return;

	int insertIndex = ([tableSourceView numberOfSelectedRows] == 0 ? [tableSourceView numberOfRows] : [tableSourceView selectedRow] + 1);
	
	[tableFields insertObject:[NSMutableDictionary 
							   dictionaryWithObjects:[NSArray arrayWithObjects:@"", @"int", @"", @"0", @"0", @"0", ([prefs boolForKey:@"NewFieldsAllowNulls"]) ? @"YES" : @"NO", @"", [prefs stringForKey:@"NullValue"], @"None", nil]
							   forKeys:[NSArray arrayWithObjects:@"Field", @"Type", @"Length", @"unsigned", @"zerofill", @"binary", @"Null", @"Key", @"Default", @"Extra", nil]]
					  atIndex:insertIndex];

	[tableSourceView reloadData];
	[tableSourceView selectRow:insertIndex byExtendingSelection:NO];
	isEditingRow = YES;
	isEditingNewRow = YES;
	currentlyEditingRow = [tableSourceView selectedRow];
	[tableSourceView editColumn:0 row:insertIndex withEvent:nil select:YES];
}

/**
 * Copies a field and goes in edit mode for the new field
 */
- (IBAction)copyField:(id)sender
{
	NSMutableDictionary *tempRow;

	if ( ![tableSourceView numberOfSelectedRows] ) {
		[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:[tableSourceView numberOfRows]-1] byExtendingSelection:NO];
	}

	// Check whether a save of the current row is required.
	if ( ![self saveRowOnDeselect] ) return;
	
	//add copy of selected row and go in edit mode
	tempRow = [NSMutableDictionary dictionaryWithDictionary:[tableFields objectAtIndex:[tableSourceView selectedRow]]];
	[tempRow setObject:[[tempRow objectForKey:@"Field"] stringByAppendingString:@"Copy"] forKey:@"Field"];
	[tempRow setObject:@"" forKey:@"Key"];
	[tempRow setObject:@"None" forKey:@"Extra"];
	[tableFields addObject:tempRow];
	[tableSourceView reloadData];
	[tableSourceView selectRow:[tableSourceView numberOfRows]-1 byExtendingSelection:NO];
	isEditingRow = YES;
	isEditingNewRow = YES;
	currentlyEditingRow = [tableSourceView selectedRow];
	[tableSourceView editColumn:0 row:[tableSourceView numberOfRows]-1 withEvent:nil select:YES];
}

/**
 * adds the index to the mysql-db and stops modal session with code 1 when success, 0 when error and -1 when no columns specified
 */
- (IBAction)addIndex:(id)sender
{
	NSString *indexName;
	NSArray *indexedColumns;
	NSMutableArray *tempIndexedColumns = [NSMutableArray array];
	NSEnumerator *enumerator;
	NSString *string;

	// Check whether a save of the current fields row is required.
	if ( ![self saveRowOnDeselect] ) return;

	if ( [[indexedColumnsField stringValue] isEqualToString:@""] ) {
		[NSApp stopModalWithCode:-1];
	} else {
		if ( [[indexNameField stringValue] isEqualToString:@"PRIMARY"] ) {
			indexName = @"";
		 } else {
			if ( [[indexNameField stringValue] isEqualToString:@""] )
			{
				indexName = @"";
			} else {
				indexName = [[indexNameField stringValue] backtickQuotedString];
			}
		}
		indexedColumns = [[indexedColumnsField stringValue] componentsSeparatedByString:@","];
		enumerator = [indexedColumns objectEnumerator];
		while ( (string = [enumerator nextObject]) ) {
			if ( ([string characterAtIndex:0] == ' ') ) {
				[tempIndexedColumns addObject:[string substringWithRange:NSMakeRange(1,([string length]-1))]];
			} else {
				[tempIndexedColumns addObject:[NSString stringWithString:string]];
			}
		}
		
		[mySQLConnection queryString:[NSString stringWithFormat:@"ALTER TABLE %@ ADD %@ %@ (%@)",
				[selectedTable backtickQuotedString], [indexTypeField titleOfSelectedItem], indexName,
				[tempIndexedColumns componentsJoinedAndBacktickQuoted]]];

		if ( [[mySQLConnection getLastErrorMessage] isEqualToString:@""] ) {
			[tableDataInstance resetColumnData];
			[tablesListInstance setStatusRequiresReload:YES];
			[self loadTable:selectedTable];
			[NSApp stopModalWithCode:1];
		} else {
			[NSApp stopModalWithCode:0];
		}
	}
}

/**
 * Ask the user to confirm that they really want to remove the selected field.
 */
- (IBAction)removeField:(id)sender
{
	if (![tableSourceView numberOfSelectedRows])
		return;

	// Check whether a save of the current row is required.
	if (![self saveRowOnDeselect]) 
		return;

	// Check if the user tries to delete the last defined field in table
	if ([tableSourceView numberOfRows] < 2) {
		NSAlert *alert = [NSAlert alertWithMessageText:NSLocalizedString(@"Error while deleting field", @"Error while deleting field")
										 defaultButton:NSLocalizedString(@"OK", @"OK button") 
									   alternateButton:nil 
										   otherButton:nil 
							 informativeTextWithFormat:NSLocalizedString(@"You cannot delete the last field in a table. Use “Remove table” (DROP TABLE) instead.",
							@"You cannot delete the last field in that table. Use “Remove table” (DROP TABLE) instead")];

		[alert setAlertStyle:NSCriticalAlertStyle];

		[alert beginSheetModalForWindow:tableWindow modalDelegate:self didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:) contextInfo:@"cannotremovefield"];
		
	}

	NSAlert *alert = [NSAlert alertWithMessageText:NSLocalizedString(@"Delete field?", @"delete field message")
									 defaultButton:NSLocalizedString(@"Delete", @"delete button") 
								   alternateButton:NSLocalizedString(@"Cancel", @"cancel button") 
									   otherButton:nil 
						 informativeTextWithFormat:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to delete the field '%@'? This action cannot be undone.", @"delete field informative message"),
																			  [[tableFields objectAtIndex:[tableSourceView selectedRow]] objectForKey:@"Field"]]];
	
	[alert setAlertStyle:NSCriticalAlertStyle];
	
	[alert beginSheetModalForWindow:tableWindow modalDelegate:self didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:) contextInfo:@"removefield"];
}

/**
 *  Ask the user to confirm that they really want to remove the selected index.
 */
- (IBAction)removeIndex:(id)sender
{
	if (![indexView numberOfSelectedRows])
		return;

	// Check whether a save of the current fields row is required.
	if (![self saveRowOnDeselect]) 
		return;

	NSAlert *alert = [NSAlert alertWithMessageText:NSLocalizedString(@"Delete Index?", @"delete index message")
									 defaultButton:NSLocalizedString(@"Delete", @"delete button") 
								   alternateButton:NSLocalizedString(@"Cancel", @"cancel button") 
									   otherButton:nil 
						 informativeTextWithFormat:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to delete the index '%@'? This action cannot be undone.", @"delete index informative message"),
																			  [[indexes objectAtIndex:[indexView selectedRow]] objectForKey:@"Key_name"]]];
	
	[alert setAlertStyle:NSCriticalAlertStyle];
	
	[alert beginSheetModalForWindow:tableWindow modalDelegate:self didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:) contextInfo:@"removeindex"];
}

#pragma mark -
#pragma mark Index sheet methods

/*
opens the indexSheet
*/
- (IBAction)openIndexSheet:(id)sender
{
	int i, code = 0;

	// Check whether a save of the current field row is required.
	if ( ![self saveRowOnDeselect] ) return;

	// Set sheet defaults - key type PRIMARY, key name PRIMARY and disabled, and blank indexed columns
	[indexTypeField selectItemAtIndex:0];
	[indexNameField setEnabled:NO];
	[indexNameField setStringValue:@"PRIMARY"];
	[indexedColumnsField setStringValue:@""];
	[indexSheet makeFirstResponder:indexedColumnsField];
	
	// Check to see whether a primary key already exists for the table, and if so select an INDEX instead
	for (i = 0; i < [indexes count]; i++) {
		if ([[[tableFields objectAtIndex:i] objectForKey:@"Key"] isEqualToString:@"PRI"]) {
			[indexTypeField selectItemAtIndex:1];
			[indexNameField setEnabled:YES];
			[indexNameField setStringValue:@""];
			[indexSheet makeFirstResponder:indexNameField];
			break;
		}
	}

	// Begin the sheet
	[NSApp beginSheet:indexSheet
			modalForWindow:tableWindow modalDelegate:self
			didEndSelector:nil contextInfo:nil];
	code = [NSApp runModalForWindow:indexSheet];
	
	[NSApp endSheet:indexSheet];
	[indexSheet orderOut:nil];

	//code == -1 -> no columns specified
	//code == 0 -> error while adding index
	//code == 1 -> index added with succes OR sheet closed without adding index
	if ( code == 0 ) {
		NSBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, 
		nil, nil, [NSString stringWithFormat:NSLocalizedString(@"Couldn't add index.\nMySQL said: %@", @"message of panel when index cannot be created"), [mySQLConnection getLastErrorMessage]]);
	} else if ( code == -1 ) {
		NSBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, 
		@selector(closeAlertSheet), nil, NSLocalizedString(@"Please insert the columns you want to index.", @"message of panel when no columns are specified to be indexed"));
	}
}

/*
closes the indexSheet without adding the index (stops modal session with code 1)
*/
- (IBAction)closeIndexSheet:(id)sender
{
	[NSApp stopModalWithCode:1];
}

/*
invoked when user chooses an index type
*/
- (IBAction)chooseIndexType:(id)sender
{
	if ( [[indexTypeField titleOfSelectedItem] isEqualToString:@"PRIMARY KEY"] ) {
		[indexNameField setEnabled:NO];
		[indexNameField setStringValue:@"PRIMARY"];
	} else {
		[indexNameField setEnabled:YES];
		if ( [[indexNameField stringValue] isEqualToString:@"PRIMARY"] )
			[indexNameField setStringValue:@""];
	}
}

/*
reopens indexSheet after errorSheet (no columns specified)
*/
- (void)closeAlertSheet
{
	[self openIndexSheet:self];
}

/*
closes the keySheet
*/
- (IBAction)closeKeySheet:(id)sender
{
	[NSApp stopModalWithCode:[sender tag]];
}


#pragma mark -
#pragma mark Additional methods

/*
sets the connection (received from TableDocument) and makes things that have to be done only once 
*/
- (void)setConnection:(CMMCPConnection *)theConnection
{
	NSEnumerator *indexColumnsEnumerator = [[indexView tableColumns] objectEnumerator];
	NSEnumerator *fieldColumnsEnumerator = [[tableSourceView tableColumns] objectEnumerator];
	id indexColumn;
	id fieldColumn;

	mySQLConnection = theConnection;

	//set up tableView
	[tableSourceView registerForDraggedTypes:[NSArray arrayWithObjects:@"SequelProPasteboard", nil]];

	while ( (indexColumn = [indexColumnsEnumerator nextObject]) ) {
		if ( [prefs boolForKey:@"UseMonospacedFonts"] ) {
			[[indexColumn dataCell] setFont:[NSFont fontWithName:@"Monaco" size:10]];
		}
		else 
		{
			[[indexColumn dataCell] setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
		}
	}
	while ( (fieldColumn = [fieldColumnsEnumerator nextObject]) ) {
		if ( [prefs boolForKey:@"UseMonospacedFonts"] ) {
			[[fieldColumn dataCell] setFont:[NSFont fontWithName:@"Monaco" size:[NSFont smallSystemFontSize]]];
		}
		else
		{
			[[fieldColumn dataCell] setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
		}
	}
}

/*
fetches the result as an array with a dictionary for each row in it
*/
- (NSArray *)fetchResultAsArray:(CMMCPResult *)theResult
{
	unsigned long numOfRows = [theResult numOfRows];
	NSMutableArray *tempResult = [NSMutableArray arrayWithCapacity:numOfRows];
	NSMutableDictionary *tempRow;
	NSArray *keys;
	id key;
	int i;
	Class nullClass = [NSNull class];
	id prefsNullValue = [prefs objectForKey:@"NullValue"];

	if (numOfRows) [theResult dataSeek:0];
	for ( i = 0 ; i < numOfRows ; i++ ) {
		tempRow = [NSMutableDictionary dictionaryWithDictionary:[theResult fetchRowAsDictionary]];

		//use NULL string from preferences instead of the NSNull oject returned by the framework
		keys = [tempRow allKeys];
		for (int i = 0; i < [keys count] ; i++) {
			key = NSArrayObjectAtIndex(keys, i);
			if ( [[tempRow objectForKey:key] isMemberOfClass:nullClass] )
				[tempRow setObject:prefsNullValue forKey:key];
		}
		// change some fields to be more human-readable or GUI compatible
		if ( [[tempRow objectForKey:@"Extra"] isEqualToString:@""] ) {
			[tempRow setObject:@"None" forKey:@"Extra"];
		}
		if ( [[tempRow objectForKey:@"Null"] isEqualToString:@"YES"] ) {
//			[tempRow setObject:[NSNumber numberWithInt:0] forKey:@"Null"];
			[tempRow setObject:@"YES" forKey:@"Null"];
		} else {
//			[tempRow setObject:[NSNumber numberWithInt:1] forKey:@"Null"];
			[tempRow setObject:@"NO" forKey:@"Null"];
		}
		[tempResult addObject:tempRow];
	}

	return tempResult;
}


/*
 * A method to be called whenever the selection changes or the table would be reloaded
 * or altered; checks whether the current row is being edited, and if so attempts to save
 * it.  Returns YES if no save was necessary or the save was successful, and NO if a save
 * was necessary but failed - also reselecting the row for re-editing.
 */
- (BOOL)saveRowOnDeselect
{
	// If no rows are currently being edited, or a save is already in progress, return success at once.
	if (!isEditingRow || isSavingRow) return YES;
	isSavingRow = YES;

	// Save any edits which have been made but not saved to the table yet.
	[tableWindow endEditingFor:nil];

	// Attempt to save the row, and return YES if the save succeeded.
	if ([self addRowToDB]) {
		isSavingRow = NO;
		return YES;
	}

	// Saving failed - reselect the old row and return failure.
	[tableSourceView selectRow:currentlyEditingRow byExtendingSelection:NO];
	isSavingRow = NO;
	return NO;
}

/**
 * tries to write row to mysql-db
 * returns YES if row written to db, otherwies NO
 * returns YES if no row is beeing edited and nothing has to be written to db
 */
- (BOOL)addRowToDB;
{
	int code;
	NSDictionary *theRow;
	NSMutableString *queryString;

	if (!isEditingRow || currentlyEditingRow == -1)
		return YES;
	
	if (alertSheetOpened)
		return NO;

	theRow = [tableFields objectAtIndex:currentlyEditingRow];
	
	if (isEditingNewRow) {
		// ADD syntax
		if ([[theRow objectForKey:@"Length"] isEqualToString:@""] || ![theRow objectForKey:@"Length"]) {
			
			queryString = [NSMutableString stringWithFormat:@"ALTER TABLE %@ ADD %@ %@",
															[selectedTable backtickQuotedString], 
															[[theRow objectForKey:@"Field"] backtickQuotedString], 
															[theRow objectForKey:@"Type"]];
		} 
		else {
			queryString = [NSMutableString stringWithFormat:@"ALTER TABLE %@ ADD %@ %@(%@)",
															[selectedTable backtickQuotedString], 
															[[theRow objectForKey:@"Field"] backtickQuotedString], 
															[theRow objectForKey:@"Type"],
															[theRow objectForKey:@"Length"]];
		}
	} 
	else {
		// CHANGE syntax
		if (([[theRow objectForKey:@"Length"] isEqualToString:@""]) || (![theRow objectForKey:@"Length"]) || ([[theRow objectForKey:@"Type"] isEqualToString:@"datetime"])) {
			
			// If the old row and new row dictionaries are equel then the user didn't actually change anything so don't continue 
			if ([oldRow isEqualToDictionary:theRow]) {
				return YES;
			}
			
			queryString = [NSMutableString stringWithFormat:@"ALTER TABLE %@ CHANGE %@ %@ %@",
															[selectedTable backtickQuotedString], 
															[[oldRow objectForKey:@"Field"] backtickQuotedString], 
															[[theRow objectForKey:@"Field"] backtickQuotedString],
															[theRow objectForKey:@"Type"]];
		} 
		else {
			// If the old row and new row dictionaries are equel then the user didn't actually change anything so don't continue 
			if ([oldRow isEqualToDictionary:theRow]) {
				return YES;
			}
			
			queryString = [NSMutableString stringWithFormat:@"ALTER TABLE %@ CHANGE %@ %@ %@(%@)",
															[selectedTable backtickQuotedString], 
															[[oldRow objectForKey:@"Field"] backtickQuotedString], 
															[[theRow objectForKey:@"Field"] backtickQuotedString],
															[theRow objectForKey:@"Type"], 
															[theRow objectForKey:@"Length"]];
		}
	}
	
	// Field specification
	if ([[theRow objectForKey:@"unsigned"] intValue] == 1) {
		[queryString appendString:@" UNSIGNED"];
	}
	
	if ( [[theRow objectForKey:@"zerofill"] intValue] == 1) {
		[queryString appendString:@" ZEROFILL"];
	}
	
	if ( [[theRow objectForKey:@"binary"] intValue] == 1) {
		[queryString appendString:@" BINARY"];
	}

	if ([[theRow objectForKey:@"Null"] isEqualToString:@"NO"]) {
		[queryString appendString:@" NOT NULL"];
	} else {
		[queryString appendString:@" NULL"];
	}
	
	// Don't provide any defaults for auto-increment fields
	if ([[theRow objectForKey:@"Extra"] isEqualToString:@"auto_increment"]) {
		[queryString appendString:@" "];
	} else {

		// If a null value has been specified, and null is allowed, specify DEFAULT NULL
		if ([[theRow objectForKey:@"Default"] isEqualToString:[prefs objectForKey:@"NullValue"]]) {
			if ([[theRow objectForKey:@"Null"] isEqualToString:@"YES"]) {
				[queryString appendString:@" DEFAULT NULL "];
			}
		
		// Otherwise, if current_timestamp was specified for timestamps, use that
		} else if ([[theRow objectForKey:@"Type"] isEqualToString:@"timestamp"] &&
					[[[theRow objectForKey:@"Default"] uppercaseString] isEqualToString:@"CURRENT_TIMESTAMP"])
		{
			[queryString appendString:@" DEFAULT CURRENT_TIMESTAMP "];

		// Otherwise, use the provided default
		} else {
			[queryString appendString:[NSString stringWithFormat:@" DEFAULT '%@' ", [mySQLConnection prepareString:[theRow objectForKey:@"Default"]]]];
		}
	}
	
	if (!(
			[[theRow objectForKey:@"Extra"] isEqualToString:@""] || 
			[[theRow objectForKey:@"Extra"] isEqualToString:@"None"]
		) && 
		[theRow objectForKey:@"Extra"] ) 
	{
		[queryString appendString:[theRow objectForKey:@"Extra"]];
	}
	
	// Asks the user to add an index to query if auto_increment is set and field isn't indexed
	if ([[theRow objectForKey:@"Extra"] isEqualToString:@"auto_increment"] && 
		([[theRow objectForKey:@"Key"] isEqualToString:@""] || 
		![theRow objectForKey:@"Key"])) 
	{
		[chooseKeyButton selectItemAtIndex:0];
		
		[NSApp beginSheet:keySheet 
		   modalForWindow:tableWindow modalDelegate:self 
		   didEndSelector:nil 
			  contextInfo:nil];
		
		code = [NSApp runModalForWindow:keySheet];
		
		[NSApp endSheet:keySheet];
		[keySheet orderOut:nil];
		
		if (code) {
			// User wants to add PRIMARY KEY
			if ([chooseKeyButton indexOfSelectedItem] == 0 ) { 
				[queryString appendString:@" PRIMARY KEY"];
				
				// Add AFTER ... only if the user added a new field
				if (isEditingNewRow) {
					[queryString appendString:[NSString stringWithFormat:@" AFTER %@", [[[tableFields objectAtIndex:(currentlyEditingRow -1)] objectForKey:@"Field"] backtickQuotedString]]];
				}
			} 
			else {
				// Add AFTER ... only if the user added a new field
				if (isEditingNewRow) {
					[queryString appendString:[NSString stringWithFormat:@" AFTER %@", [[[tableFields objectAtIndex:(currentlyEditingRow -1)] objectForKey:@"Field"] backtickQuotedString]]];
				} 
				
				[queryString appendString:[NSString stringWithFormat:@", ADD %@ (%@)", [chooseKeyButton titleOfSelectedItem], [[theRow objectForKey:@"Field"] backtickQuotedString]]];
			}
		}
	} 
	// Add AFTER ... only if the user added a new field
	else if (isEditingNewRow) {
		[queryString appendString:[NSString stringWithFormat:@" AFTER %@", [[[tableFields objectAtIndex:(currentlyEditingRow -1)] objectForKey:@"Field"] backtickQuotedString]]];
	}

	// Execute query
	[mySQLConnection queryString:queryString];

	if ([[mySQLConnection getLastErrorMessage] isEqualToString:@""]) {
		isEditingRow = NO;
		isEditingNewRow = NO;
		currentlyEditingRow = -1;
		
		[tableDataInstance resetColumnData];
		[tablesListInstance setStatusRequiresReload:YES];
		[self loadTable:selectedTable];

		// Mark the content table for refresh
		[tablesListInstance setContentRequiresReload:YES];

		return YES;
	} 
	else {
		alertSheetOpened = YES;
		
		// Problem: alert sheet doesn't respond to first click
		if (isEditingNewRow) {
			NSBeginAlertSheet(NSLocalizedString(@"Error adding field", @"error adding field message"), 
							  NSLocalizedString(@"OK", @"OK button"), 
							  NSLocalizedString(@"Cancel", @"cancel button"), nil, tableWindow, self, @selector(sheetDidEnd:returnCode:contextInfo:), nil, @"addrow", 
							  [NSString stringWithFormat:NSLocalizedString(@"An error occurred when trying to add the field '%@'.\n\nMySQL said: %@", @"error adding field informative message"), 
							  [theRow objectForKey:@"Field"], [mySQLConnection getLastErrorMessage]]);
		} 
		else {
			NSBeginAlertSheet(NSLocalizedString(@"Error changing field", @"error changing field message"), 
							  NSLocalizedString(@"OK", @"OK button"), 
							  NSLocalizedString(@"Cancel", @"cancel button"), nil, tableWindow, self, @selector(sheetDidEnd:returnCode:contextInfo:), nil, @"addrow", 
							  [NSString stringWithFormat:NSLocalizedString(@"An error occurred when trying to change the field '%@'.\n\nMySQL said: %@", @"error changing field informative message"), 
							  [theRow objectForKey:@"Field"], [mySQLConnection getLastErrorMessage]]);
		}
		
		return NO;
	}
}

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(NSString *)contextInfo
{
	/*
	 if contextInfo == addrow: remain in edit-mode if user hits OK, otherwise cancel editing
	 if contextInfo == removefield: removes row from mysql-db if user hits ok
	 if contextInfo == removeindex: removes index from mysql-db if user hits ok
	 if contextInfo == cannotremovefield: do nothing
	 */

	if ( [contextInfo isEqualToString:@"addrow"] ) {
		[sheet orderOut:self];
		
		alertSheetOpened = NO;
		if ( returnCode == NSAlertDefaultReturn ) {
			//problem: reentering edit mode for first cell doesn't function
			[tableSourceView editColumn:0 row:[tableSourceView selectedRow] withEvent:nil select:YES];
		} else {
			if ( !isEditingNewRow ) {
				[tableFields replaceObjectAtIndex:[tableSourceView selectedRow]
							withObject:[NSMutableDictionary dictionaryWithDictionary:oldRow]];
				isEditingRow = NO;
			} else {
				[tableFields removeObjectAtIndex:[tableSourceView selectedRow]];
				isEditingRow = NO;
				isEditingNewRow = NO;
			}
			currentlyEditingRow = -1;
		}
		[tableSourceView reloadData];
	} else if ( [contextInfo isEqualToString:@"removefield"] ) {
		if ( returnCode == NSAlertDefaultReturn ) {
			//remove row
			[mySQLConnection queryString:[NSString stringWithFormat:@"ALTER TABLE %@ DROP %@",
					[selectedTable backtickQuotedString], [[[tableFields objectAtIndex:[tableSourceView selectedRow]] objectForKey:@"Field"] backtickQuotedString]]];
			
			if ( [[mySQLConnection getLastErrorMessage] isEqualToString:@""] ) {
				[tableDataInstance resetColumnData];
				[tablesListInstance setStatusRequiresReload:YES];
				[self loadTable:selectedTable];

				// Mark the content table cache for refresh
				[tablesListInstance setContentRequiresReload:YES];
			} else {
				[self performSelector:@selector(showErrorSheetWith:) 
					withObject:[NSArray arrayWithObjects:NSLocalizedString(@"Error", @"error"),
									[NSString stringWithFormat:NSLocalizedString(@"Couldn't remove field %@.\nMySQL said: %@", @"message of panel when field cannot be removed"),
											[[tableFields objectAtIndex:[tableSourceView selectedRow]] objectForKey:@"Field"],
											[mySQLConnection getLastErrorMessage]],
								nil] 
					afterDelay:0.3];
			}
		}
	} else if ( [contextInfo isEqualToString:@"removeindex"] ) {
		if ( returnCode == NSAlertDefaultReturn ) {
			//remove index
			if ( [[[indexes objectAtIndex:[indexView selectedRow]] objectForKey:@"Key_name"] isEqualToString:@"PRIMARY"] ) {
				[mySQLConnection queryString:[NSString stringWithFormat:@"ALTER TABLE %@ DROP PRIMARY KEY", [selectedTable backtickQuotedString]]];
			} else {
				[mySQLConnection queryString:[NSString stringWithFormat:@"ALTER TABLE %@ DROP INDEX %@",
						[selectedTable backtickQuotedString], [[[indexes objectAtIndex:[indexView selectedRow]] objectForKey:@"Key_name"] backtickQuotedString]]];
			}
		
			if ( [[mySQLConnection getLastErrorMessage] isEqualToString:@""] ) {
				[tableDataInstance resetColumnData];
				[tablesListInstance setStatusRequiresReload:YES];
				[self loadTable:selectedTable];
			} else {
				[self performSelector:@selector(showErrorSheetWith:) 
					withObject:[NSArray arrayWithObjects:NSLocalizedString(@"Error", @"error"),
									[NSString stringWithFormat:NSLocalizedString(@"Couldn't remove index.\nMySQL said: %@", @"message of panel when index cannot be removed"), 
											[mySQLConnection getLastErrorMessage]],
								nil] 
					afterDelay:0.3];
			}
		}
	} else if ( [contextInfo isEqualToString:@"cannotremovefield"]) {
		;
	}
	
}

/*
 * Show Error sheet (can be called from inside of a endSheet selector)
 * via [self performSelector:@selector(showErrorSheetWithTitle:) withObject: afterDelay:]
 */
-(void)showErrorSheetWith:(id)error
{
	// error := first object is the title , second the message, only one button OK
	NSBeginAlertSheet([error objectAtIndex:0], NSLocalizedString(@"OK", @"OK button"), 
			nil, nil, tableWindow, self, nil, nil, nil,
			[error objectAtIndex:1]);
}

/**
 * This method is called as part of Key Value Observing which is used to watch for preference changes which effect the interface.
 */
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{	
	if ([keyPath isEqualToString:@"DisplayTableViewVerticalGridlines"]) {
        [tableSourceView setGridStyleMask:([[change objectForKey:NSKeyValueChangeNewKey] boolValue]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];
		[indexView setGridStyleMask:([[change objectForKey:NSKeyValueChangeNewKey] boolValue]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];
	}
}

#pragma mark -
#pragma mark Getter methods

/*
get the default value for a specified field
*/
- (NSString *)defaultValueForField:(NSString *)field
{
	if ( ![defaultValues objectForKey:field] ) {
		return [prefs objectForKey:@"NullValue"];	
	} else if ( [[defaultValues objectForKey:field] isMemberOfClass:[NSNull class]] ) {
		return [prefs objectForKey:@"NullValue"];
	} else {
		return [defaultValues objectForKey:field];
	}
}

/*
returns an array containing the field names of the selected table
*/
- (NSArray *)fieldNames
{
	NSMutableArray *tempArray = [NSMutableArray array];
	NSEnumerator *enumerator;
	id field;
	
	//load table if not already done
	if ( ![tablesListInstance structureLoaded] ) {
		[self loadTable:[tablesListInstance tableName]];
	}
	
	//get field names
	enumerator = [tableFields objectEnumerator];
	while ( (field = [enumerator nextObject]) ) {
		[tempArray addObject:[field objectForKey:@"Field"]];
	}
  
	return [NSArray arrayWithArray:tempArray];
}

/*
returns a dictionary containing enum/set field names as key and possible values as array
*/
- (NSDictionary *)enumFields
{
	return [NSDictionary dictionaryWithDictionary:enumFields];
}

- (NSArray *)tableStructureForPrint
{
	CMMCPResult *queryResult;
	NSMutableArray *tempResult = [NSMutableArray array];
	int i;
	
	queryResult = [mySQLConnection queryString:[NSString stringWithFormat:@"SHOW COLUMNS FROM %@", [selectedTable backtickQuotedString]]];
	
	if ([queryResult numOfRows]) [queryResult dataSeek:0];
	[tempResult addObject:[queryResult fetchFieldNames]];
	for ( i = 0 ; i < [queryResult numOfRows] ; i++ ) {
		[tempResult addObject:[queryResult fetchRowAsArray]];
	}
	
	return tempResult;
}

#pragma mark -
#pragma mark TableView datasource methods

- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	if ( aTableView == tableSourceView ) {
		return [tableFields count];
	} else {
		return [indexes count];
	}
}

- (id)tableView:(NSTableView *)aTableView
			objectValueForTableColumn:(NSTableColumn *)aTableColumn
			row:(int)rowIndex
{
	id theRow, theValue;
	
	if ( aTableView == tableSourceView ) {
		theRow = [tableFields objectAtIndex:rowIndex];
	} else {
		theRow = [indexes objectAtIndex:rowIndex];
	}
	theValue = [theRow objectForKey:[aTableColumn identifier]];

	return theValue;
}

- (void)tableView:(NSTableView *)aTableView
			setObjectValue:(id)anObject
			forTableColumn:(NSTableColumn *)aTableColumn
			row:(int)rowIndex
{
    //make sure that the drag operation is for the right table view
    if (aTableView!=tableSourceView) return;

	if ( !isEditingRow ) {
		[oldRow setDictionary:[tableFields objectAtIndex:rowIndex]];
		isEditingRow = YES;
		currentlyEditingRow = rowIndex;
	}
	if ( anObject ) {
		[[tableFields objectAtIndex:rowIndex] setObject:anObject forKey:[aTableColumn identifier]];
	} else {
		[[tableFields objectAtIndex:rowIndex] setObject:@"" forKey:[aTableColumn identifier]];
	}
}

/*
Begin a drag and drop operation from the table - copy a single dragged row to the drag pasteboard.
*/
- (BOOL)tableView:(NSTableView *)tableView writeRows:(NSArray*)rows toPasteboard:(NSPasteboard*)pboard
{
    //make sure that the drag operation is started from the right table view
    if (tableView!=tableSourceView) return NO;
    
    
	int originalRow;
	NSArray *pboardTypes;

	// Check whether a save of the current field row is required.
	if ( ![self saveRowOnDeselect] ) return NO;

	if ( ([rows count] == 1)  && (tableView == tableSourceView) ) {
		pboardTypes=[NSArray arrayWithObjects:@"SequelProPasteboard", nil];
		originalRow = [[rows objectAtIndex:0] intValue];

		[pboard declareTypes:pboardTypes owner:nil];
		[pboard setString:[[NSNumber numberWithInt:originalRow] stringValue] forType:@"SequelProPasteboard"];

		return YES;
	} else {
		return NO;
	}
}

/*
Determine whether to allow a drag and drop operation on this table - for the purposes of drag reordering,
validate that the original source is of the correct type and within the same table, and that the drag
would result in a position change.
*/
- (NSDragOperation)tableView:(NSTableView*)tableView validateDrop:(id <NSDraggingInfo>)info proposedRow:(int)row
	proposedDropOperation:(NSTableViewDropOperation)operation
{
    //make sure that the drag operation is for the right table view
    if (tableView!=tableSourceView) return NO;

	NSArray *pboardTypes = [[info draggingPasteboard] types];
	int originalRow;

	// Ensure the drop is of the correct type
	if (operation == NSTableViewDropAbove && row != -1 && [pboardTypes containsObject:@"SequelProPasteboard"]) {
	
		// Ensure the drag originated within this table
		if ([info draggingSource] == tableView) {
			originalRow = [[[info draggingPasteboard] stringForType:@"SequelProPasteboard"] intValue];
			
			if (row != originalRow && row != (originalRow+1)) {
				return NSDragOperationMove;
			}
		}
	}

	return NSDragOperationNone;
}

/*
 * Having validated a drop, perform the field/column reordering to match.
 */
- (BOOL)tableView:(NSTableView*)tableView acceptDrop:(id <NSDraggingInfo>)info row:(int)destinationRowIndex dropOperation:(NSTableViewDropOperation)operation
{
    //make sure that the drag operation is for the right table view
    if (tableView!=tableSourceView) return NO;

	int originalRowIndex;
	NSMutableString *queryString;
	NSDictionary *originalRow;

	// Extract the original row position from the pasteboard and retrieve the details
	originalRowIndex = [[[info draggingPasteboard] stringForType:@"SequelProPasteboard"] intValue];
	originalRow = [[NSDictionary alloc] initWithDictionary:[tableFields objectAtIndex:originalRowIndex]];

	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryWillBePerformed" object:self];

	// Begin construction of the reordering query
	queryString = [NSMutableString stringWithFormat:@"ALTER TABLE %@ MODIFY COLUMN %@ %@", [selectedTable backtickQuotedString],
		[[originalRow objectForKey:@"Field"] backtickQuotedString],
		[originalRow objectForKey:@"Type"]];

	// Add the length parameter if necessary
	if ( [originalRow objectForKey:@"Length"] && ![[originalRow objectForKey:@"Length"] isEqualToString:@""]) {
		[queryString appendString:[NSString stringWithFormat:@"(%@)", [originalRow objectForKey:@"Length"]]];
	}

	// Add unsigned, zerofill, binary, not null if necessary
	if ([[originalRow objectForKey:@"unsigned"] isEqualToString:@"1"]) {
		[queryString appendString:@" UNSIGNED"];
	}
	if ([[originalRow objectForKey:@"zerofill"] isEqualToString:@"1"]) {
		[queryString appendString:@" ZEROFILL"];
	}
	if ([[originalRow objectForKey:@"binary"] isEqualToString:@"1"]) {
		[queryString appendString:@" BINARY"];
	}
	if ([[originalRow objectForKey:@"Null"] isEqualToString:@"NO"] ) {
		[queryString appendString:@" NOT NULL"];
	}
	if (![[originalRow objectForKey:@"Extra"] isEqualToString:@"None"] ) {
		[queryString appendString:@" "];
		[queryString appendString:[[originalRow objectForKey:@"Extra"] uppercaseString]];
	}

	// Add the default value
	if ([[originalRow objectForKey:@"Default"] isEqualToString:[prefs objectForKey:@"NullValue"]]) {
		if ([[originalRow objectForKey:@"Null"] isEqualToString:@"YES"]) {
			[queryString appendString:@" DEFAULT NULL"];
		}
	} else if ( [[originalRow objectForKey:@"Type"] isEqualToString:@"timestamp"] && ([[[originalRow objectForKey:@"Default"] uppercaseString] isEqualToString:@"CURRENT_TIMESTAMP"]) ) {
			[queryString appendString:@" DEFAULT CURRENT_TIMESTAMP"];
	} else {
		[queryString appendString:[NSString stringWithFormat:@" DEFAULT '%@'", [mySQLConnection prepareString:[originalRow objectForKey:@"Default"]]]];
	}

	// Add the new location
	if ( destinationRowIndex == 0 ){
		[queryString appendString:@" FIRST"];
	} else {
		[queryString appendString:[NSString stringWithFormat:@" AFTER %@",
						[[[tableFields objectAtIndex:destinationRowIndex-1] objectForKey:@"Field"] backtickQuotedString]]];
	}

	// Run the query; report any errors, or reload the table on success
	[mySQLConnection queryString:queryString];
	if ( ![[mySQLConnection getLastErrorMessage] isEqualTo:@""] ) {
		NSBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil,
			[NSString stringWithFormat:NSLocalizedString(@"Couldn't move field. MySQL said: %@", @"message of panel when field cannot be added in drag&drop operation"), [mySQLConnection getLastErrorMessage]]);
	} else {
		[tableDataInstance resetColumnData];
		[tablesListInstance setStatusRequiresReload:YES];
		[self loadTable:selectedTable];

		// Mark the content table cache for refresh
		[tablesListInstance setContentRequiresReload:YES];

		if ( originalRowIndex < destinationRowIndex ) {
			[tableSourceView selectRow:destinationRowIndex-1 byExtendingSelection:NO];
		} else {
			[tableSourceView selectRow:destinationRowIndex byExtendingSelection:NO];
		}
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryHasBeenPerformed" object:self];
	
	[originalRow release];
	return YES;
}

#pragma mark -
#pragma mark TableView delegate methods

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{

	//check for which table view the selection changed
	if ([aNotification object] == tableSourceView) {
		// If we are editing a row, attempt to save that row - if saving failed, reselect the edit row.
		if ( isEditingRow && [tableSourceView selectedRow] != currentlyEditingRow ) {
			[self saveRowOnDeselect];
			isEditingRow = NO;
		}
		[copyFieldButton setEnabled:YES];

		// check if there is currently a field selected
		// and change button state accordingly
		if ([tableSourceView numberOfSelectedRows] > 0 && [tablesListInstance tableType] == SP_TABLETYPE_TABLE) {
			[removeFieldButton setEnabled:YES];
		} else {
			[removeFieldButton setEnabled:NO];
			[copyFieldButton setEnabled:NO];
		}
	}
	else if ([aNotification object] == indexView) {
		// check if there is currently an index selected
		// and change button state accordingly
		if ([indexView numberOfSelectedRows] > 0 && [tablesListInstance tableType] == SP_TABLETYPE_TABLE) {
			[removeIndexButton setEnabled:YES];
		} else {
			[removeIndexButton setEnabled:NO];
		}
	}
}

/*
traps enter and esc and make/cancel editing without entering next row
*/
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
	int row, column;

	row = [tableSourceView editedRow];
	column = [tableSourceView editedColumn];

	 if (  [textView methodForSelector:command] == [textView methodForSelector:@selector(insertNewline:)] ||
				[textView methodForSelector:command] == [textView methodForSelector:@selector(insertTab:)] ) //trap enter and tab
	 {
		//save current line
		[[control window] makeFirstResponder:control];
		if ( column == 9 ) {
			if ( [self addRowToDB] && [textView methodForSelector:command] == [textView methodForSelector:@selector(insertTab:)] ) {
				if ( row < ([tableSourceView numberOfRows] - 1) ) {
					[tableSourceView selectRow:row+1 byExtendingSelection:NO];
					[tableSourceView editColumn:0 row:row+1 withEvent:nil select:YES];
				} else {
					[tableSourceView selectRow:0 byExtendingSelection:NO];
					[tableSourceView editColumn:0 row:0 withEvent:nil select:YES];
				}
			}
		} else {
			if ( column == 2 ) {
				[tableSourceView editColumn:column+4 row:row withEvent:nil select:YES];
			} else if ( column == 6 ) {
				[tableSourceView editColumn:column+2 row:row withEvent:nil select:YES];
			} else {
				[tableSourceView editColumn:column+1 row:row withEvent:nil select:YES];
			}
		}
		return TRUE;
		 
	 } else if (  [[control window] methodForSelector:command] == [[control window] methodForSelector:@selector(_cancelKey:)] ||
					[textView methodForSelector:command] == [textView methodForSelector:@selector(complete:)] ) {
		//abort editing
		[control abortEditing];
		if ( isEditingRow && !isEditingNewRow ) {
			isEditingRow = NO;
			[tableFields replaceObjectAtIndex:row withObject:[NSMutableDictionary dictionaryWithDictionary:oldRow]];
		} else if ( isEditingNewRow ) {
			isEditingRow = NO;
			isEditingNewRow = NO;
			[tableFields removeObjectAtIndex:row];
			[tableSourceView reloadData];
		}
		currentlyEditingRow = -1;
		return TRUE;
	 } else {
		 return FALSE;
	 }
}


/*
 * Modify cell display by disabling table cells when a view is selected, meaning structure/index
 * is uneditable.
 */
- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex {
    
    //make sure that the message is from the right table view
    if (tableView!=tableSourceView) return;

	[aCell setEnabled:([tablesListInstance tableType] == SP_TABLETYPE_TABLE)];
}

#pragma mark -
#pragma mark SplitView delegate methods

- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview
{
	return YES;
}

- (float)splitView:(NSSplitView *)sender constrainMaxCoordinate:(float)proposedMax ofSubviewAt:(int)offset
{
		return proposedMax - 150;
}

- (float)splitView:(NSSplitView *)sender constrainMinCoordinate:(float)proposedMin ofSubviewAt:(int)offset
{
		return proposedMin + 150;
}

- (NSRect)splitView:(NSSplitView *)splitView additionalEffectiveRectOfDividerAtIndex:(int)dividerIndex
{	
	return [structureGrabber convertRect:[structureGrabber bounds] toView:splitView];
}

// Last but not least
- (id)init
{
	if ((self = [super init])) {
		tableFields = [[NSMutableArray alloc] init];
		indexes     = [[NSMutableArray alloc] init];
		oldRow      = [[NSMutableDictionary alloc] init];
		enumFields  = [[NSMutableDictionary alloc] init];
		
		currentlyEditingRow = -1;
		
		prefs = [NSUserDefaults standardUserDefaults];
	}

	return self;
}

- (void)awakeFromNib
{
	// Set the structure and index view's vertical gridlines if required
	[tableSourceView setGridStyleMask:([prefs boolForKey:@"DisplayTableViewVerticalGridlines"]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];
	[indexView setGridStyleMask:([prefs boolForKey:@"DisplayTableViewVerticalGridlines"]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];
}

- (void)dealloc
{	
	[tableFields release];
	[indexes release];
	[oldRow release];
	[defaultValues release];
	[enumFields release];
	
	[super dealloc];
}

@end