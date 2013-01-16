//
//  $Id: SPMySQLStringAdditions.m 3511 2012-03-17 15:32:00Z rowanb@gmail.com $
//
//  SPMySQLStringAdditions.h
//  SPMySQLFramework
//
//  Created by Rowan Beentje (rowan.beent.je) on February 8, 2012
//  Copyright (c) 2012 Rowan Beentje. All rights reserved.
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

#import "SPMySQLStringAdditions.h"

@implementation NSString (SPMySQLStringAdditions)

/**
 * Returns the string quoted with backticks as required for MySQL identifiers
 * eg.:  tablename    =>   `tablename`
 *       my`table     =>   `my``table`
 */
- (NSString *)mySQLBacktickQuotedString
{
	return [NSString stringWithFormat: @"`%@`", [self stringByReplacingOccurrencesOfString:@"`" withString:@"``"]];
}

/**
 * Returns the string quoted with ticks as required for MySQL identifiers
 * eg.:  tablename    =>   'tablename'
 *       my'table     =>   'my''table'
 */
- (NSString *)mySQLTickQuotedString
{
	return [NSString stringWithFormat: @"'%@'", [self stringByReplacingOccurrencesOfString:@"'" withString:@"''"]];
}

- (NSString *)stringByEscapingForURLQuery
{
    static CFStringRef leaveAlone = CFSTR(" ");
	static CFStringRef toEscape = CFSTR("\n\r:/=,!$&'()*+;[]@#?%");
    
    NSString *result = self;
	CFStringRef escapedStr = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)self, leaveAlone, toEscape, kCFStringEncodingUTF8);
    
	if (escapedStr) {
		NSMutableString *mutable = [NSMutableString stringWithString:(NSString *)escapedStr];
		CFRelease(escapedStr);
        
		[mutable replaceOccurrencesOfString:@" " withString:@"+" options:0 range:NSMakeRange(0, [mutable length])];
		result = mutable;
	}
    
	return result;  
	
}

- (NSString *)stringByUnescapingFromURLQuery
{
    static CFStringRef space = CFSTR(" ");
    
    return [(NSString *)CFURLCreateStringByReplacingPercentEscapesUsingEncoding(kCFAllocatorDefault, (CFStringRef)self, space, kCFStringEncodingUTF8) autorelease];
}

@end