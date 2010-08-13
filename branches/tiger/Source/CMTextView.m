//
//  CMTextView.m
//  sequel-pro
//
//  Created by Carsten Blüm.
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
//  Or mail to <lorenz@textor.ch>

#import "CMTextView.h"
#import "TableDocument.h"
#import "SPStringAdditions.h"
#import "SPTextViewAdditions.h"

/*
 * Include all the extern variables and prototypes required for flex (used for syntax highlighting)
 */
#import "SPEditorTokens.h"
extern int yylex();
extern int yyuoffset, yyuleng;
typedef struct yy_buffer_state *YY_BUFFER_STATE;
void yy_switch_to_buffer(YY_BUFFER_STATE);
YY_BUFFER_STATE yy_scan_string (const char *);

#define kAPlinked   @"Linked" // attribute for a via auto-pair inserted char
#define kAPval      @"linked"
#define kWQquoted   @"Quoted" // set via lex to indicate a quoted string
#define kWQval      @"quoted"
#define kSQLkeyword @"SQLkw"  // attribute for found SQL keywords
#define kQuote      @"Quote"

#define MYSQL_DOC_SEARCH_URL @"http://dev.mysql.com/doc/refman/%@/en/%@.html"

@implementation CMTextView

/*
 * Add a menu item to context menu for looking up mysql documentation.
 */
- (NSMenu *)menuForEvent:(NSEvent *)event 
{	
	// Set title of the menu item
	lookupInDocumentationTitle = NSLocalizedString(@"Lookup In MySQL Documentation", @"Lookup In MySQL Documentation");
	
	// Add the menu item if it doesn't yet exist
	NSMenu *menu = [[self class] defaultMenu];
	
	if ([[[self class] defaultMenu] itemWithTitle:lookupInDocumentationTitle] == nil) {
		
		[menu insertItem:[NSMenuItem separatorItem] atIndex:3];
		[menu insertItemWithTitle:lookupInDocumentationTitle action:@selector(lookupSelectionInDocumentation) keyEquivalent:@"" atIndex:4];
	}
	
    return menu;
}

/*
 * Open the refman if available or a search for the current selection or current word on mysql.com 
 */
- (void)lookupSelectionInDocumentation 
{	
	// Get the major MySQL server version in the form of x.x, which is basically the first 3 characters of the returned version string
	NSString *version = [[(TableDocument *)[[self window] delegate] mySQLVersion] substringToIndex:3];
	
	// Get the current selection and encode it to be used in a URL
	NSString *keyword = [[[self string] substringWithRange:[self getRangeForCurrentWord]] lowercaseString];
	
	// Remove whitespace and newlines
	keyword = [keyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	// Remove whitespace and newlines within the keyword
	NSMutableString *mutableKeyword = [keyword mutableCopy];
	[mutableKeyword replaceOccurrencesOfString:@" " withString:@"" options:0 range:NSMakeRange(0, [mutableKeyword length])];
	[mutableKeyword replaceOccurrencesOfString:@"\n" withString:@"" options:0 range:NSMakeRange(0, [mutableKeyword length])];
	keyword = [NSString stringWithString:mutableKeyword];
	[mutableKeyword release];

	// Open MySQL Documentation search in browser using the terms
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:MYSQL_DOC_SEARCH_URL, version, [keyword stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding]]];
	
	[[NSWorkspace sharedWorkspace] openURL:url];
}

/*
 * Disable the lookup in documentation function when getRangeForCurrentWord returns zero length. 
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem 
{	
	// Enable or disable the lookup in documentation menu item depending on whether there is a 
	// selection and whether it is a reasonable length.
	if ([menuItem action] == @selector(lookupSelectionInDocumentation)) {
		return (([self getRangeForCurrentWord].length) || ([self getRangeForCurrentWord].length > 256));
	}
	
	return YES;
}

/*
 * Checks if the char after the current caret position/selection matches a supplied attribute
 */
- (BOOL) isNextCharMarkedBy:(id)attribute
{
	unsigned int caretPosition = [self selectedRange].location;

	// Perform bounds checking
	if (caretPosition >= [[self string] length]) return NO;
	
	// Perform the check
	if ([[self textStorage] attribute:attribute atIndex:caretPosition effectiveRange:nil])
		return YES;

	return NO;
}

/*
 * Checks if the caret is wrapped by auto-paired characters.
 * e.g. [| := caret]: "|" 
 */
- (BOOL) areAdjacentCharsLinked
{
	unsigned int caretPosition = [self selectedRange].location;
	unichar leftChar, matchingChar;

	// Perform bounds checking
	if ([self selectedRange].length) return NO;
	if (caretPosition < 1) return NO;
	if (caretPosition >= [[self string] length]) return NO;

	// Check the character to the left of the cursor and set the pairing character if appropriate
	leftChar = [[self string] characterAtIndex:caretPosition - 1];
	if (leftChar == '(')
		matchingChar = ')';
	else if (leftChar == '"' || leftChar == '`' || leftChar == '\'')
		matchingChar = leftChar;
	else
		return NO;

	// Check that the pairing character exists after the caret, and is tagged with the link attribute
	if (matchingChar == [[self string] characterAtIndex:caretPosition]
		&& [[self textStorage] attribute:kAPlinked atIndex:caretPosition effectiveRange:nil]) {
		return YES;
	}

	return NO;
}

/*
 * If the textview has a selection, wrap it with the supplied prefix and suffix strings;
 * return whether or not any wrap was performed.
 */
- (BOOL) wrapSelectionWithPrefix:(NSString *)prefix suffix:(NSString *)suffix
{

	// Only proceed if a selection is active
	if ([self selectedRange].length == 0)
		return NO;

	// Replace the current selection with the selected string wrapped in prefix and suffix
	[self insertText:
		[NSString stringWithFormat:@"%@%@%@", 
			prefix,
			[[self string] substringWithRange:[self selectedRange]],
			suffix
		]
	];
	return YES;
}

/*
 * Copy selected text chunk as RTF to preserve syntax highlighting
 */
- (void)copyAsRTF
{

	NSPasteboard *pb = [NSPasteboard generalPasteboard];
	NSTextStorage *textStorage = [self textStorage];
	NSData *rtf = [textStorage RTFFromRange:[self selectedRange]
		documentAttributes:nil];
	
	if (rtf)
	{
		[pb declareTypes:[NSArray arrayWithObject:NSRTFPboardType] owner:self];
		[pb setData:rtf forType:NSRTFPboardType];
	}
}

/*
 * Selects the line lineNumber relatively to a selection (if given) and scrolls to it
 */
- (void) selectLineNumber:(unsigned int)lineNumber ignoreLeadingNewLines:(BOOL)ignLeadingNewLines
{
	NSRange selRange;
	NSArray *lineRanges;
	if([self selectedRange].length)
		lineRanges = [[[self string] substringWithRange:[self selectedRange]] lineRangesForRange:NSMakeRange(0, [self selectedRange].length)];
	else
		lineRanges = [[self string] lineRangesForRange:NSMakeRange(0, [[self string] length])];
	int offset = 0;
	if(ignLeadingNewLines) // ignore leading empty lines
	{
		int arrayCount = [lineRanges count];
		int i;
		for (i = 0; i < arrayCount; i++) {
			if(NSRangeFromString([lineRanges objectAtIndex:i]).length > 0)
				break;
			offset++;
		}
	}
	selRange = NSRangeFromString([lineRanges objectAtIndex:lineNumber-1+offset]);

	// adjust selRange if a selection was given
	if([self selectedRange].length)
		selRange.location += [self selectedRange].location;
	[self setSelectedRange:selRange];
	[self scrollRangeToVisible:selRange];
}

/*
 * Handle some keyDown events in order to provide autopairing functionality (if enabled).
 */
- (void) keyDown:(NSEvent *)theEvent
{
	
	long allFlags = (NSShiftKeyMask|NSControlKeyMask|NSAlternateKeyMask|NSCommandKeyMask);
	
	// Check if user pressed ⌥ to allow composing of accented characters.
	// e.g. for US keyboard "⌥u a" to insert ä
	// or for non-US keyboards to allow to enter dead keys
	// e.g. for German keyboard ` is a dead key, press space to enter `
	if (([theEvent modifierFlags] & allFlags) == NSAlternateKeyMask || [[theEvent characters] length] == 0)
	{
		[super keyDown: theEvent];
		return;
	}

	NSString *characters = [theEvent characters];
	NSString *charactersIgnMod = [theEvent charactersIgnoringModifiers];
	unichar insertedCharacter = [characters characterAtIndex:0];
	long curFlags = ([theEvent modifierFlags] & allFlags);
	

	// Note: switch(insertedCharacter) {} does not work instead use charactersIgnoringModifiers
	if([charactersIgnMod isEqualToString:@"c"]) // ^C copy as RTF
		if(curFlags==(NSControlKeyMask))
		{
			[self copyAsRTF];
			return;
		}

	// Only process for character autopairing if autopairing is enabled and a single character is being added.
	if (autopairEnabled && characters && [characters length] == 1) {

		delBackwardsWasPressed = NO;

		NSString *matchingCharacter = nil;
		BOOL processAutopair = NO, skipTypedLinkedCharacter = NO;
		NSRange currentRange;

		// When a quote character is being inserted into a string quoted with other
		// quote characters, or if it's the same character but is escaped, don't
		// automatically match it.
		if(
			// Only for " ` or ' quote characters
			(insertedCharacter == '\'' || insertedCharacter == '"' || insertedCharacter == '`')

			// And if the next char marked as linked auto-pair
			&& [self isNextCharMarkedBy:kAPlinked]

			// And we are inside a quoted string
			&& [self isNextCharMarkedBy:kWQquoted]

			// And there is no selection, just the text caret
			&& ![self selectedRange].length

			&& (
				// And the user is inserting an escaped string
				[[self string] characterAtIndex:[self selectedRange].location-1] == '\\'
				
				// Or the user is inserting a character not matching the characters used to quote this string
				|| [[self string] characterAtIndex:[self selectedRange].location] != insertedCharacter
			)
		)
		{
			[super keyDown: theEvent];
			return;
		}

		// If the caret is inside a text string, without any selection, skip autopairing.
		// There is one exception to this - if the caret is before a linked pair character,
		// processing continues in order to check whether the next character should be jumped
		// over; e.g. [| := caret]: "foo|" and press " => only caret will be moved "foo"|
		if(![self isNextCharMarkedBy:kAPlinked] && [self isNextCharMarkedBy:kWQquoted] && ![self selectedRange].length) {
			[super keyDown:theEvent];
			return;
		}

		// Check whether the submitted character should trigger autopair processing.
		switch (insertedCharacter)
		{
			case '(':
				matchingCharacter = @")";
				processAutopair = YES;
				break;
			case '"':
				matchingCharacter = @"\"";
				processAutopair = YES;
				skipTypedLinkedCharacter = YES;
				break;
			case '`':
				matchingCharacter = @"`";
				processAutopair = YES;
				skipTypedLinkedCharacter = YES;
				break;
			case '\'':
				matchingCharacter = @"'";
				processAutopair = YES;
				skipTypedLinkedCharacter = YES;
				break;
			case ')':
				skipTypedLinkedCharacter = YES;
				break;
		}

		// Check to see whether the next character should be compared to the typed character;
		// if it matches the typed character, and is marked with the is-linked-pair attribute,
		// select the next character and replace it with the typed character.  This allows
		// a normally quoted string to be typed in full, with the autopair appearing as a hint and
		// then being automatically replaced when the user types it.
		if (skipTypedLinkedCharacter) {
			currentRange = [self selectedRange];
			if (currentRange.location != NSNotFound && currentRange.length == 0) {
				if ([self isNextCharMarkedBy:kAPlinked]) {
					if ([[[self textStorage] string] characterAtIndex:currentRange.location] == insertedCharacter) {
						currentRange.length = 1;
						[self setSelectedRange:currentRange];
						processAutopair = NO;
					}
				}
			}
		}

		// If an appropriate character has been typed, and a matching character has been set,
		// some form of autopairing is required.
		if (processAutopair && matchingCharacter) {

			// Check to see whether several characters are selected, and if so, wrap them with
			// the auto-paired characters.  This returns false if the selection has zero length.
			if ([self wrapSelectionWithPrefix:characters suffix:matchingCharacter])
				return;
			
			// Otherwise, start by inserting the original character - the first half of the autopair.
			[super keyDown:theEvent];
			
			// Then process the second half of the autopair - the matching character.
			currentRange = [self selectedRange];
			if (currentRange.location != NSNotFound) {
				NSTextStorage *textStorage = [self textStorage];

				// Register the auto-pairing for undo
				[self shouldChangeTextInRange:currentRange replacementString:matchingCharacter];

				// Insert the matching character and give it the is-linked-pair-character attribute
				[self replaceCharactersInRange:currentRange withString:matchingCharacter];
				currentRange.length = 1;
				[textStorage addAttribute:kAPlinked value:kAPval range:currentRange];

				// Restore the original selection.
				currentRange.length=0;
				[self setSelectedRange:currentRange];
			}
			return;
		}
	}

	// The default action is to perform the normal key-down action.
	[super keyDown:theEvent];
	
}


- (void) deleteBackward:(id)sender
{

	// If the caret is currently inside a marked auto-pair, delete the characters on both sides
	// of the caret.
	NSRange currentRange = [self selectedRange];
	if (currentRange.length == 0 && currentRange.location > 0 && [self areAdjacentCharsLinked])
		[self setSelectedRange:NSMakeRange(currentRange.location - 1,2)];
	
	// Avoid auto-uppercasing if resulting word would be a SQL keyword;
	// e.g. type inta| and deleteBackward:
	delBackwardsWasPressed = YES;	

	[super deleteBackward:sender];

}


/*
 * Handle special commands - see NSResponder.h for a sample list.
 * This subclass currently handles insertNewline: in order to preserve indentation
 * when adding newlines.
 */
- (void) doCommandBySelector:(SEL)aSelector
{

	// Handle newlines, adding any indentation found on the current line to the new line - ignoring the enter key if appropriate
    if (aSelector == @selector(insertNewline:)
		&& autoindentEnabled
		&& (!autoindentIgnoresEnter || [[NSApp currentEvent] keyCode] != 0x4C))
	{
		NSString *textViewString = [[self textStorage] string];
		NSString *currentLine, *indentString = nil;
		NSScanner *whitespaceScanner;
		NSRange currentLineRange;

		// Extract the current line based on the text caret or selection start position
		currentLineRange = [textViewString lineRangeForRange:NSMakeRange([self selectedRange].location, 0)];
		currentLine = [[NSString alloc] initWithString:[textViewString substringWithRange:currentLineRange]];

		// Scan all indentation characters on the line into a string
		whitespaceScanner = [[NSScanner alloc] initWithString:currentLine];
		[whitespaceScanner setCharactersToBeSkipped:nil];
		[whitespaceScanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&indentString];
		[whitespaceScanner release];
		[currentLine release];

		// Always add the newline, whether or not we want to indent the next line
		[self insertNewline:self];

		// Replicate the indentation on the previous line if one was found.
		if (indentString) [self insertText:indentString];

		// Return to avoid the original implementation, preventing double linebreaks
		return;
	}
	[super doCommandBySelector:aSelector];
}


/*
 * Shifts the selection, if any, rightwards by indenting any selected lines with one tab.
 * If the caret is within a line, the selection is not changed after the index; if the selection
 * has length, all lines crossed by the length are indented and fully selected.
 * Returns whether or not an indentation was performed.
 */
- (BOOL) shiftSelectionRight
{
	NSString *textViewString = [[self textStorage] string];
	NSRange currentLineRange;
	NSArray *lineRanges;
	NSString *tabString = @"\t";
	int i, indentedLinesLength = 0;

	if ([self selectedRange].location == NSNotFound) return NO;

	// Indent the currently selected line if the caret is within a single line
	if ([self selectedRange].length == 0) {
		NSRange currentLineRange;

		// Extract the current line range based on the text caret
		currentLineRange = [textViewString lineRangeForRange:[self selectedRange]];

		// Register the indent for undo
		[self shouldChangeTextInRange:NSMakeRange(currentLineRange.location, 0) replacementString:tabString];

		// Insert the new tab
		[self replaceCharactersInRange:NSMakeRange(currentLineRange.location, 0) withString:tabString];

		return YES;
	}

	// Otherwise, the selection has a length - get an array of current line ranges for the specified selection
	lineRanges = [textViewString lineRangesForRange:[self selectedRange]];

	// Loop through the ranges, storing a count of the overall length.
	for (i = 0; i < [lineRanges count]; i++) {
		currentLineRange = NSRangeFromString([lineRanges objectAtIndex:i]);
		indentedLinesLength += currentLineRange.length + 1;

		// Register the indent for undo
		[self shouldChangeTextInRange:NSMakeRange(currentLineRange.location+i, 0) replacementString:tabString];

		// Insert the new tab
		[self replaceCharactersInRange:NSMakeRange(currentLineRange.location+i, 0) withString:tabString];
	}

	// Select the entirety of the new range
	[self setSelectedRange:NSMakeRange(NSRangeFromString([lineRanges objectAtIndex:0]).location, indentedLinesLength)];

	return YES;
}


/*
 * Shifts the selection, if any, leftwards by un-indenting any selected lines by one tab if possible.
 * If the caret is within a line, the selection is not changed after the undent; if the selection has
 * length, all lines crossed by the length are un-indented and fully selected.
 * Returns whether or not an indentation was performed.
 */
- (BOOL) shiftSelectionLeft
{
	NSString *textViewString = [[self textStorage] string];
	NSRange currentLineRange;
	NSArray *lineRanges;
	int i, unindentedLines = 0, unindentedLinesLength = 0;

	if ([self selectedRange].location == NSNotFound) return NO;

	// Undent the currently selected line if the caret is within a single line
	if ([self selectedRange].length == 0) {
		NSRange currentLineRange;

		// Extract the current line range based on the text caret
		currentLineRange = [textViewString lineRangeForRange:[self selectedRange]];

		// Ensure that the line has length and that the first character is a tab
		if (currentLineRange.length < 1
			|| [textViewString characterAtIndex:currentLineRange.location] != '\t')
			return NO;

		// Register the undent for undo
		[self shouldChangeTextInRange:NSMakeRange(currentLineRange.location, 1) replacementString:@""];

		// Remove the tab
		[self replaceCharactersInRange:NSMakeRange(currentLineRange.location, 1) withString:@""];

		return YES;
	}

	// Otherwise, the selection has a length - get an array of current line ranges for the specified selection
	lineRanges = [textViewString lineRangesForRange:[self selectedRange]];

	// Loop through the ranges, storing a count of the total lines changed and the new length.
	for (i = 0; i < [lineRanges count]; i++) {
		currentLineRange = NSRangeFromString([lineRanges objectAtIndex:i]);
		unindentedLinesLength += currentLineRange.length;
		
		// Ensure that the line has length and that the first character is a tab
		if (currentLineRange.length < 1
			|| [textViewString characterAtIndex:currentLineRange.location-unindentedLines] != '\t')
			continue;

		// Register the undent for undo
		[self shouldChangeTextInRange:NSMakeRange(currentLineRange.location-unindentedLines, 1) replacementString:@""];

		// Remove the tab
		[self replaceCharactersInRange:NSMakeRange(currentLineRange.location-unindentedLines, 1) withString:@""];
		
		// As a line has been unindented, modify counts and lengths
		unindentedLines++;
		unindentedLinesLength--;
	}

	// If a change was made, select the entirety of the new range and return success
	if (unindentedLines) {
		[self setSelectedRange:NSMakeRange(NSRangeFromString([lineRanges objectAtIndex:0]).location, unindentedLinesLength)];
		return YES;
	}

	return NO;
}

/*
 * Handle autocompletion, returning a list of suggested completions for the supplied character range.
 */
- (NSArray *)completionsForPartialWordRange:(NSRange)charRange indexOfSelectedItem:(int *)index
{

	// Check if the caret is inside quotes "" or ''; if so 
	// return the normal word suggestion due to the spelling's settings
	if([[self textStorage] attribute:kQuote atIndex:charRange.location effectiveRange:nil])
		return [[NSSpellChecker sharedSpellChecker] completionsForPartialWordRange:NSMakeRange(0,charRange.length) inString:[[self string] substringWithRange:charRange] language:nil inSpellDocumentWithTag:0];

	NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@" \t\r\n,()\"'`-!"];
	NSArray *textViewWords     = [[self string] componentsSeparatedByCharactersInSet:separators];
	NSString *partialString    = [[self string] substringWithRange:charRange];
	unsigned int partialLength = [partialString length];

	id tableNames = [[[[self window] delegate] valueForKeyPath:@"tablesListInstance"] valueForKey:@"tables"];
	
	//unsigned int options = NSCaseInsensitiveSearch | NSAnchoredSearch;
	//NSRange partialRange = NSMakeRange(0, partialLength);
	
	NSMutableArray *compl = [[NSMutableArray alloc] initWithCapacity:32];
	
	NSMutableArray *possibleCompletions = [NSMutableArray arrayWithArray:textViewWords];
	[possibleCompletions addObjectsFromArray:[self keywords]];
	[possibleCompletions addObjectsFromArray:tableNames];
	
	// Add column names to completions list for currently selected table
	if ([[[self window] delegate] table] != nil) {
		id columnNames = [[[[self window] delegate] valueForKeyPath:@"tableDataInstance"] valueForKey:@"columnNames"];
		[possibleCompletions addObjectsFromArray:columnNames];
	}

	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF beginswith[cd] %@ AND length > %d", partialString, partialLength];
	NSArray *matchingCompletions = [[possibleCompletions filteredArrayUsingPredicate:predicate] sortedArrayUsingSelector:@selector(compare:)];

	unsigned i, insindex;
	
	insindex = 0;
	for (i = 0; i < [matchingCompletions count]; i++)
	{
		NSString* obj = [matchingCompletions objectAtIndex:i];
		if(![compl containsObject:obj])
			if ([partialString isEqualToString:[obj substringToIndex:partialLength]])
				// Matches case --> Insert at beginning of completion list
				[compl insertObject:obj atIndex:insindex++];
			else
				// Not matching case --> Insert at end of completion list
				[compl addObject:obj];
	}

	return [compl autorelease];
}


/*
 * Hook to invoke the auto-uppercasing of SQL keywords after pasting
 */
- (void)paste:(id)sender
{

	[super paste:sender];
	// Invoke the auto-uppercasing of SQL keywords via an additional trigger
	[self insertText:@""];
}


/*
 * List of keywords for autocompletion. If you add a keyword here,
 * it should also be added to the flex file SPEditorTokens.l
 */
-(NSArray *)keywords
{
	return [NSArray arrayWithObjects:
	@"ACCESSIBLE",
	@"ACTION",
	@"ADD",
	@"AFTER",
	@"AGAINST",
	@"AGGREGATE",
	@"ALGORITHM",
	@"ALL",
	@"ALTER",
	@"ALTER COLUMN",
	@"ALTER DATABASE",
	@"ALTER EVENT",
	@"ALTER FUNCTION",
	@"ALTER LOGFILE GROUP",
	@"ALTER PROCEDURE",
	@"ALTER SCHEMA",
	@"ALTER SERVER",
	@"ALTER TABLE",
	@"ALTER TABLESPACE",
	@"ALTER VIEW",
	@"ANALYZE",
	@"ANALYZE TABLE",
	@"AND",
	@"ANY",
	@"AS",
	@"ASC",
	@"ASCII",
	@"ASENSITIVE",
	@"AT",
	@"AUTHORS",
	@"AUTOEXTEND_SIZE",
	@"AUTO_INCREMENT",
	@"AVG",
	@"AVG_ROW_LENGTH",
	@"BACKUP",
	@"BACKUP TABLE",
	@"BEFORE",
	@"BEGIN",
	@"BETWEEN",
	@"BIGINT",
	@"BINARY",
	@"BINLOG",
	@"BIT",
	@"BLOB",
	@"BOOL",
	@"BOOLEAN",
	@"BOTH",
	@"BTREE",
	@"BY",
	@"BYTE",
	@"CACHE",
	@"CACHE INDEX",
	@"CALL",
	@"CASCADE",
	@"CASCADED",
	@"CASE",
	@"CHAIN",
	@"CHANGE",
	@"CHANGED",
	@"CHAR",
	@"CHARACTER",
	@"CHARACTER SET",
	@"CHARSET",
	@"CHECK",
	@"CHECK TABLE",
	@"CHECKSUM",
	@"CHECKSUM TABLE",
	@"CIPHER",
	@"CLIENT",
	@"CLOSE",
	@"COALESCE",
	@"CODE",
	@"COLLATE",
	@"COLLATION",
	@"COLUMN",
	@"COLUMNS",
	@"COLUMN_FORMAT"
	@"COMMENT",
	@"COMMIT",
	@"COMMITTED",
	@"COMPACT",
	@"COMPLETION",
	@"COMPRESSED",
	@"CONCURRENT",
	@"CONDITION",
	@"CONNECTION",
	@"CONSISTENT",
	@"CONSTRAINT",
	@"CONTAINS",
	@"CONTINUE",
	@"CONTRIBUTORS",
	@"CONVERT",
	@"CREATE",
	@"CREATE DATABASE",
	@"CREATE EVENT",
	@"CREATE FUNCTION",
	@"CREATE INDEX",
	@"CREATE LOGFILE GROUP",
	@"CREATE PROCEDURE",
	@"CREATE SCHEMA",
	@"CREATE TABLE",
	@"CREATE TABLESPACE",
	@"CREATE TRIGGER",
	@"CREATE USER",
	@"CREATE VIEW",
	@"CROSS",
	@"CUBE",
	@"CURRENT_DATE",
	@"CURRENT_TIME",
	@"CURRENT_TIMESTAMP",
	@"CURRENT_USER",
	@"CURSOR",
	@"DATA",
	@"DATABASE",
	@"DATABASES",
	@"DATAFILE",
	@"DATE",
	@"DATETIME",
	@"DAY",
	@"DAY_HOUR",
	@"DAY_MICROSECOND",
	@"DAY_MINUTE",
	@"DAY_SECOND",
	@"DEALLOCATE",
	@"DEALLOCATE PREPARE",
	@"DEC",
	@"DECIMAL",
	@"DECLARE",
	@"DEFAULT",
	@"DEFINER",
	@"DELAYED",
	@"DELAY_KEY_WRITE",
	@"DELETE",
	@"DESC",
	@"DESCRIBE",
	@"DES_KEY_FILE",
	@"DETERMINISTIC",
	@"DIRECTORY",
	@"DISABLE",
	@"DISCARD",
	@"DISK",
	@"DISTINCT",
	@"DISTINCTROW",
	@"DIV",
	@"DO",
	@"DOUBLE",
	@"DROP",
	@"DROP DATABASE",
	@"DROP EVENT",
	@"DROP FOREIGN KEY",
	@"DROP FUNCTION",
	@"DROP INDEX",
	@"DROP LOGFILE GROUP",
	@"DROP PREPARE",
	@"DROP PRIMARY KEY",
	@"DROP PREPARE",
	@"DROP PROCEDURE",
	@"DROP SCHEMA",
	@"DROP SERVER",
	@"DROP TABLE",
	@"DROP TABLESPACE",
	@"DROP TRIGGER",
	@"DROP USER",
	@"DROP VIEW",
	@"DUAL",
	@"DUMPFILE",
	@"DUPLICATE",
	@"DYNAMIC",
	@"EACH",
	@"ELSE",
	@"ELSEIF",
	@"ENABLE",
	@"ENCLOSED",
	@"END",
	@"ENDS",
	@"ENGINE",
	@"ENGINES",
	@"ENUM",
	@"ERRORS",
	@"ESCAPE",
	@"ESCAPED",
	@"EVENT",
	@"EVENTS",
	@"EVERY",
	@"EXECUTE",
	@"EXISTS",
	@"EXIT",
	@"EXPANSION",
	@"EXPLAIN",
	@"EXTENDED",
	@"EXTENT_SIZE",
	@"FALSE",
	@"FAST",
	@"FETCH",
	@"FIELDS",
	@"FILE",
	@"FIRST",
	@"FIXED",
	@"FLOAT",
	@"FLOAT4",
	@"FLOAT8",
	@"FLUSH",
	@"FOR",
	@"FORCE",
	@"FOREIGN KEY",
	@"FOREIGN",
	@"FOUND",
	@"FRAC_SECOND",
	@"FROM",
	@"FULL",
	@"FULLTEXT",
	@"FUNCTION",
	@"GEOMETRY",
	@"GEOMETRYCOLLECTION",
	@"GET_FORMAT",
	@"GLOBAL",
	@"GRANT",
	@"GRANTS",
	@"GROUP",
	@"HANDLER",
	@"HASH",
	@"HAVING",
	@"HELP",
	@"HIGH_PRIORITY",
	@"HOSTS",
	@"HOUR",
	@"HOUR_MICROSECOND",
	@"HOUR_MINUTE",
	@"HOUR_SECOND",
	@"IDENTIFIED",
	@"IF",
	@"IGNORE",
	@"IMPORT",
	@"IN",
	@"INDEX",
	@"INDEXES",
	@"INFILE",
	@"INITIAL_SIZE",
	@"INNER",
	@"INNOBASE",
	@"INNODB",
	@"INOUT",
	@"INSENSITIVE",
	@"INSERT",
	@"INSERT_METHOD",
	@"INSTALL",
	@"INSTALL PLUGIN",
	@"INT",
	@"INT1",
	@"INT2",
	@"INT3",
	@"INT4",
	@"INT8",
	@"INTEGER",
	@"INTERVAL",
	@"INTO",
	@"INVOKER",
	@"IO_THREAD",
	@"IS",
	@"ISOLATION",
	@"ISSUER",
	@"ITERATE",
	@"JOIN",
	@"KEY",
	@"KEYS",
	@"KEY_BLOCK_SIZE",
	@"KILL",
	@"LANGUAGE",
	@"LAST",
	@"LEADING",
	@"LEAVE",
	@"LEAVES",
	@"LEFT",
	@"LESS",
	@"LEVEL",
	@"LIKE",
	@"LIMIT",
	@"LINEAR",
	@"LINES",
	@"LINESTRING",
	@"LIST",
	@"LOAD DATA",
	@"LOAD INDEX INTO CACHE",
	@"LOCAL",
	@"LOCALTIME",
	@"LOCALTIMESTAMP",
	@"LOCK",
	@"LOCK TABLES",
	@"LOCKS",
	@"LOGFILE",
	@"LOGS",
	@"LONG",
	@"LONGBLOB",
	@"LONGTEXT",
	@"LOOP",
	@"LOW_PRIORITY",
	@"MASTER",
	@"MASTER_CONNECT_RETRY",
	@"MASTER_HOST",
	@"MASTER_LOG_FILE",
	@"MASTER_LOG_POS",
	@"MASTER_PASSWORD",
	@"MASTER_PORT",
	@"MASTER_SERVER_ID",
	@"MASTER_SSL",
	@"MASTER_SSL_CA",
	@"MASTER_SSL_CAPATH",
	@"MASTER_SSL_CERT",
	@"MASTER_SSL_CIPHER",
	@"MASTER_SSL_KEY",
	@"MASTER_USER",
	@"MATCH",
	@"MAXVALUE",
	@"MAX_CONNECTIONS_PER_HOUR",
	@"MAX_QUERIES_PER_HOUR",
	@"MAX_ROWS",
	@"MAX_SIZE",
	@"MAX_UPDATES_PER_HOUR",
	@"MAX_USER_CONNECTIONS",
	@"MEDIUM",
	@"MEDIUMBLOB",
	@"MEDIUMINT",
	@"MEDIUMTEXT",
	@"MEMORY",
	@"MERGE",
	@"MICROSECOND",
	@"MIDDLEINT",
	@"MIGRATE",
	@"MINUTE",
	@"MINUTE_MICROSECOND",
	@"MINUTE_SECOND",
	@"MIN_ROWS",
	@"MOD",
	@"MODE",
	@"MODIFIES",
	@"MODIFY",
	@"MONTH",
	@"MULTILINESTRING",
	@"MULTIPOINT",
	@"MULTIPOLYGON",
	@"MUTEX",
	@"NAME",
	@"NAMES",
	@"NATIONAL",
	@"NATURAL",
	@"NCHAR",
	@"NDB",
	@"NDBCLUSTER",
	@"NEW",
	@"NEXT",
	@"NO",
	@"NODEGROUP",
	@"NONE",
	@"NOT",
	@"NO_WAIT",
	@"NO_WRITE_TO_BINLOG",
	@"NULL",
	@"NUMERIC",
	@"NVARCHAR",
	@"OFFSET",
	@"OLD_PASSWORD",
	@"ON",
	@"ONE",
	@"ONE_SHOT",
	@"OPEN",
	@"OPTIMIZE",
	@"OPTIMIZE TABLE",
	@"OPTION",
	@"OPTIONALLY",
	@"OPTIONS",
	@"OR",
	@"ORDER",
	@"OUT",
	@"OUTER",
	@"OUTFILE",
	@"PACK_KEYS",
	@"PARSER",
	@"PARTIAL",
	@"PARTITION",
	@"PARTITIONING",
	@"PARTITIONS",
	@"PASSWORD",
	@"PHASE",
	@"PLUGIN",
	@"PLUGINS",
	@"POINT",
	@"POLYGON",
	@"PRECISION",
	@"PREPARE",
	@"PRESERVE",
	@"PREV",
	@"PRIMARY",
	@"PRIVILEGES",
	@"PROCEDURE",
	@"PROCESS",
	@"PROCESSLIST",
	@"PURGE",
	@"QUARTER",
	@"QUERY",
	@"QUICK",
	@"RANGE",
	@"READ",
	@"READS",
	@"READ_ONLY",
	@"READ_WRITE",
	@"REAL",
	@"REBUILD",
	@"RECOVER",
	@"REDOFILE",
	@"REDO_BUFFER_SIZE",
	@"REDUNDANT",
	@"REFERENCES",
	@"REGEXP",
	@"RELAY_LOG_FILE",
	@"RELAY_LOG_POS",
	@"RELAY_THREAD",
	@"RELEASE",
	@"RELOAD",
	@"REMOVE",
	@"RENAME",
	@"RENAME DATABASE",
	@"RENAME TABLE",
	@"REORGANIZE",
	@"REPAIR",
	@"REPAIR TABLE",
	@"REPEAT",
	@"REPEATABLE",
	@"REPLACE",
	@"REPLICATION",
	@"REQUIRE",
	@"RESET",
	@"RESET MASTER",
	@"RESTORE",
	@"RESTORE TABLE",
	@"RESTRICT",
	@"RESUME",
	@"RETURN",
	@"RETURNS",
	@"REVOKE",
	@"RIGHT",
	@"RLIKE",
	@"ROLLBACK",
	@"ROLLUP",
	@"ROUTINE",
	@"ROW",
	@"ROWS",
	@"ROW_FORMAT",
	@"RTREE",
	@"SAVEPOINT",
	@"SCHEDULE",
	@"SCHEDULER",
	@"SCHEMA",
	@"SCHEMAS",
	@"SECOND",
	@"SECOND_MICROSECOND",
	@"SECURITY",
	@"SELECT",
	@"SENSITIVE",
	@"SEPARATOR",
	@"SERIAL",
	@"SERIALIZABLE",
	@"SESSION",
	@"SET",
	@"SET PASSWORD",
	@"SHARE",
	@"SHOW",
	@"SHOW BINARY LOGS",
	@"SHOW BINLOG EVENTS",
	@"SHOW CHARACTER SET",
	@"SHOW COLLATION",
	@"SHOW COLUMNS",
	@"SHOW CONTRIBUTORS",
	@"SHOW CREATE DATABASE",
	@"SHOW CREATE EVENT",
	@"SHOW CREATE FUNCTION",
	@"SHOW CREATE PROCEDURE",
	@"SHOW CREATE SCHEMA",
	@"SHOW CREATE TABLE",
	@"SHOW CREATE TRIGGERS",
	@"SHOW CREATE VIEW",
	@"SHOW DATABASES",
	@"SHOW ENGINE",
	@"SHOW ENGINES",
	@"SHOW ERRORS",
	@"SHOW EVENTS",
	@"SHOW FIELDS",
	@"SHOW FUNCTION CODE",
	@"SHOW FUNCTION STATUS",
	@"SHOW GRANTS",
	@"SHOW INDEX",
	@"SHOW INNODB STATUS",
	@"SHOW KEYS",
	@"SHOW MASTER LOGS",
	@"SHOW MASTER STATUS",
	@"SHOW OPEN TABLES",
	@"SHOW PLUGINS",
	@"SHOW PRIVILEGES",
	@"SHOW PROCEDURE CODE",
	@"SHOW PROCEDURE STATUS",
	@"SHOW PROFILE",
	@"SHOW PROFILES",
	@"SHOW PROCESSLIST",
	@"SHOW SCHEDULER STATUS",
	@"SHOW SCHEMAS",
	@"SHOW SLAVE HOSTS",
	@"SHOW SLAVE STATUS",
	@"SHOW STATUS",
	@"SHOW STORAGE ENGINES",
	@"SHOW TABLE STATUS",
	@"SHOW TABLE TYPES",
	@"SHOW TABLES",
	@"SHOW TRIGGERS",
	@"SHOW VARIABLES",
	@"SHOW WARNINGS",
	@"SHUTDOWN",
	@"SIGNED",
	@"SIMPLE",
	@"SLAVE",
	@"SMALLINT",
	@"SNAPSHOT",
	@"SOME",
	@"SONAME",
	@"SOUNDS",
	@"SPATIAL",
	@"SPECIFIC",
	@"SQL",
	@"SQLEXCEPTION",
	@"SQLSTATE",
	@"SQLWARNING",
	@"SQL_BIG_RESULT",
	@"SQL_BUFFER_RESULT",
	@"SQL_CACHE",
	@"SQL_CALC_FOUND_ROWS",
	@"SQL_NO_CACHE",
	@"SQL_SMALL_RESULT",
	@"SQL_THREAD",
	@"SQL_TSI_DAY",
	@"SQL_TSI_FRAC_SECOND",
	@"SQL_TSI_HOUR",
	@"SQL_TSI_MINUTE",
	@"SQL_TSI_MONTH",
	@"SQL_TSI_QUARTER",
	@"SQL_TSI_SECOND",
	@"SQL_TSI_WEEK",
	@"SQL_TSI_YEAR",
	@"SSL",
	@"START",
	@"START TRANSACTION",
	@"STARTING",
	@"STARTS",
	@"STATUS",
	@"STOP",
	@"STORAGE",
	@"STRAIGHT_JOIN",
	@"STRING",
	@"SUBJECT",
	@"SUBPARTITION",
	@"SUBPARTITIONS",
	@"SUPER",
	@"SUSPEND",
	@"TABLE",
	@"TABLES",
	@"TABLESPACE",
	@"TEMPORARY",
	@"TEMPTABLE",
	@"TERMINATED",
	@"TEXT",
	@"THAN",
	@"THEN",
	@"TIME",
	@"TIMESTAMP",
	@"TIMESTAMPADD",
	@"TIMESTAMPDIFF",
	@"TINYBLOB",
	@"TINYINT",
	@"TINYTEXT",
	@"TO",
	@"TRAILING",
	@"TRANSACTION",
	@"TRIGGER",
	@"TRIGGERS",
	@"TRUE",
	@"TRUNCATE",
	@"TYPE",
	@"TYPES",
	@"UNCOMMITTED",
	@"UNDEFINED",
	@"UNDO",
	@"UNDOFILE",
	@"UNDO_BUFFER_SIZE",
	@"UNICODE",
	@"UNINSTALL",
	@"UNINSTALL PLUGIN",
	@"UNION",
	@"UNIQUE",
	@"UNKNOWN",
	@"UNLOCK",
	@"UNLOCK TABLES",
	@"UNSIGNED",
	@"UNTIL",
	@"UPDATE",
	@"UPGRADE",
	@"USAGE",
	@"USE",
	@"USER",
	@"USER_RESOURCES",
	@"USE_FRM",
	@"USING",
	@"UTC_DATE",
	@"UTC_TIME",
	@"UTC_TIMESTAMP",
	@"VALUE",
	@"VALUES",
	@"VARBINARY",
	@"VARCHAR",
	@"VARCHARACTER",
	@"VARIABLES",
	@"VARYING",
	@"VIEW",
	@"WAIT",
	@"WARNINGS",
	@"WEEK",
	@"WHEN",
	@"WHERE",
	@"WHILE",
	@"WITH",
	@"WORK",
	@"WRITE",
	@"X509",
	@"XA",
	@"XOR",
	@"YEAR",
	@"YEAR_MONTH",
	@"ZEROFILL",
	nil];
}


/*
 * Set whether this text view should apply the indentation on the current line to new lines.
 */
- (void)setAutoindent:(BOOL)enableAutoindent
{
	autoindentEnabled = enableAutoindent;
}

/*
 * Retrieve whether this text view applies indentation on the current line to new lines.
 */
- (BOOL)autoindent
{
	return autoindentEnabled;
}

/*
 * Set whether this text view should not autoindent when the Enter key is used, as opposed
 * to the return key.  Also catches function-return.
 */
- (void)setAutoindentIgnoresEnter:(BOOL)enableAutoindentIgnoresEnter
{
	autoindentIgnoresEnter = enableAutoindentIgnoresEnter;
}

/*
 * Retrieve whether this text view should not autoindent when the Enter key is used.
 */
- (BOOL)autoindentIgnoresEnter
{
	return autoindentIgnoresEnter;
}

/*
 * Set whether this text view should automatically create the matching closing char for ", ', ` and ( chars.
 */
- (void)setAutopair:(BOOL)enableAutopair
{
	autopairEnabled = enableAutopair;
}

/*
 * Retrieve whether this text view automatically creates the matching closing char for ", ', ` and ( chars.
 */
- (BOOL)autopair
{
	return autopairEnabled;
}

/*
 * Set whether SQL keywords should be automatically uppercased.
 */
- (void)setAutouppercaseKeywords:(BOOL)enableAutouppercaseKeywords
{
	autouppercaseKeywordsEnabled = enableAutouppercaseKeywords;
}

/*
 * Retrieve whether SQL keywords should be automaticallyuppercased.
 */
- (BOOL)autouppercaseKeywords
{
	return autouppercaseKeywordsEnabled;
}

/*******************
SYNTAX HIGHLIGHTING!
*******************/
- (void)awakeFromNib
/*
 * Sets self as delegate for the textView's textStorage to enable syntax highlighting,
 * and set defaults for general usage
 */
{
    [[self textStorage] setDelegate:self];

	autoindentEnabled = YES;
	autopairEnabled = YES;
	autoindentIgnoresEnter = NO;
	autouppercaseKeywordsEnabled = YES;
	delBackwardsWasPressed = NO;

    lineNumberView = [[NoodleLineNumberView alloc] initWithScrollView:scrollView];
    [scrollView setVerticalRulerView:lineNumberView];
    [scrollView setHasHorizontalRuler:NO];
    [scrollView setHasVerticalRuler:YES];
    [scrollView setRulersVisible:YES];
}

- (void)textStorageDidProcessEditing:(NSNotification *)notification
/*
 *  Performs syntax highlighting.
 *  This method recolors the entire text on every keypress. For performance reasons, this function does
 *  nothing if the text is more than 20 KB.
 *  
 *  The main bottleneck is the [NSTextStorage addAttribute:value:range:] method - the parsing itself is really fast!
 *  
 *  Some sample code from Andrew Choi ( http://members.shaw.ca/akochoi-old/blog/2003/11-09/index.html#3 ) has been reused.
 */
{
	NSTextStorage *textStore = [notification object];

	//make sure that the notification is from the correct textStorage object
	if (textStore!=[self textStorage]) return;


	NSColor *commentColor   = [NSColor colorWithDeviceRed:0.000 green:0.455 blue:0.000 alpha:1.000];
	NSColor *quoteColor     = [NSColor colorWithDeviceRed:0.769 green:0.102 blue:0.086 alpha:1.000];
	NSColor *keywordColor   = [NSColor colorWithDeviceRed:0.200 green:0.250 blue:1.000 alpha:1.000];
	NSColor *backtickColor  = [NSColor colorWithDeviceRed:0.0 green:0.0 blue:0.658 alpha:1.000];
	NSColor *numericColor   = [NSColor colorWithDeviceRed:0.506 green:0.263 blue:0.0 alpha:1.000];
	NSColor *variableColor  = [NSColor colorWithDeviceRed:0.5 green:0.5 blue:0.5 alpha:1.000];

	NSColor *tokenColor;

	int token;
	NSRange textRange, tokenRange;

	textRange = NSMakeRange(0, [textStore length]);

	//don't color texts longer than about 20KB. would be too slow
	if (textRange.length > 20000) return; 

	//first remove the old colors
	[textStore removeAttribute:NSForegroundColorAttributeName range:textRange];


	//initialise flex
	yyuoffset = 0; yyuleng = 0;
	yy_switch_to_buffer(yy_scan_string([[textStore string] UTF8String]));

	//now loop through all the tokens
	while (token=yylex()){
		switch (token) {
			case SPT_SINGLE_QUOTED_TEXT:
			case SPT_DOUBLE_QUOTED_TEXT:
			    tokenColor = quoteColor;
			    break;
			case SPT_BACKTICK_QUOTED_TEXT:
			    tokenColor = backtickColor;
			    break;
			case SPT_RESERVED_WORD:
			    tokenColor = keywordColor;
			    break;
			case SPT_NUMERIC:
				tokenColor = numericColor;
				break;
			case SPT_COMMENT:
			    tokenColor = commentColor;
			    break;
			case SPT_VARIABLE:
			    tokenColor = variableColor;
			    break;
			default:
			    tokenColor = nil;
		}

		if (!tokenColor) continue;

		tokenRange = NSMakeRange(yyuoffset, yyuleng);

		// make sure that tokenRange is valid (and therefore within textRange)
		// otherwise a bug in the lex code could cause the the TextView to crash
		tokenRange = NSIntersectionRange(tokenRange, textRange); 
		if (!tokenRange.length) continue;

		// If the current token is marked as SQL keyword, uppercase it if required.
		unsigned long tokenEnd = tokenRange.location+tokenRange.length-1; 
		// Check the end of the token
		if (autouppercaseKeywordsEnabled && !delBackwardsWasPressed
			&& [[self textStorage] attribute:kSQLkeyword atIndex:tokenEnd effectiveRange:nil])
			// check if next char is not a kSQLkeyword or current kSQLkeyword is at the end; 
			// if so then upper case keyword if not already done
			// @try catch() for catching valid index esp. after deleteBackward:
			{
				NSString* curTokenString = [[self string] substringWithRange:tokenRange];
				BOOL doIt = NO;
				@try
				{
						doIt = ![[self textStorage] attribute:kSQLkeyword atIndex:tokenEnd+1  effectiveRange:nil];
				} @catch(id ae) { doIt = YES;  }

				if(doIt && ![[curTokenString uppercaseString] isEqualToString:curTokenString])
				{
					// Register it for undo works only partly for now, at least the uppercased keyword will be selected
					[self shouldChangeTextInRange:tokenRange replacementString:[curTokenString uppercaseString]];
					[self replaceCharactersInRange:tokenRange withString:[curTokenString uppercaseString]];
				}
			}

		[textStore addAttribute: NSForegroundColorAttributeName
						  value: tokenColor
						  range: tokenRange ];

		// Add an attribute to be used in the auto-pairing (keyDown:)
		// to disable auto-pairing if caret is inside of any token found by lex.
		// For discussion: maybe change it later (only for quotes not keywords?)
		[textStore addAttribute: kWQquoted 
						  value: kWQval 
						  range: tokenRange ];


		// Mark each SQL keyword for auto-uppercasing and do it for the next textStorageDidProcessEditing: event.
		// Performing it one token later allows words which start as reserved keywords to be entered.
		if(token == SPT_RESERVED_WORD)
			[textStore addAttribute: kSQLkeyword
							  value: kWQval
							  range: tokenRange ];
		// Add an attribute to be used to distinguish quotes from keywords etc.
		// used e.g. in completion suggestions
		if(token == SPT_DOUBLE_QUOTED_TEXT || token == SPT_SINGLE_QUOTED_TEXT)
			[textStore addAttribute: kQuote
							  value: kWQval
							  range: tokenRange ];
	}
}

@end