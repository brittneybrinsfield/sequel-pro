//
//  MCPAttribute.m
//  MCPModeler
//
//  Created by Serge Cohen (serge.cohen@m4x.org) on 09/08/04.
//  Copyright 2004 Serge Cohen. All rights reserved.
//
//  This code is free software; you can redistribute it and/or modify it under
//  the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or any later version.
//
//  This code is distributed in the hope that it will be useful, but WITHOUT ANY
//  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
//  FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
//  details.
//
//  For a copy of the GNU General Public License, visit <http://www.gnu.org/> or
//  write to the Free Software Foundation, Inc., 59 Temple Place--Suite 330,
//  Boston, MA 02111-1307, USA.
//
//  More info at <http://mysql-cocoa.sourceforge.net/>
//

#import "MCPAttribute.h"

#import "MCPEntrepriseNotifications.h"

#import "MCPModel.h"
#import "MCPClassDescription.h"
#import "MCPRelation.h"
#import "MCPJoin.h"

static NSArray    *MCPRecognisedInternalType;

@interface MCPAttribute (Private)

- (void)setValueClassName:(NSString *) iClassName;

@end

@implementation MCPAttribute

#pragma mark Class methods
+ (void) initialize
{
	if (self == [MCPAttribute class]) {
		[self setVersion:010101]; // Ma.Mi.Re -> MaMiRe
		MCPRecognisedInternalType = [[NSArray alloc] initWithObjects:@"NSCalendarDate", @"NSData", @"NSNumber", @"NSString", nil];
		[self setKeys:[NSArray arrayWithObject:@"internalType"] triggerChangeNotificationsForDependentKey:@"valueClassName"];
		[self setKeys:[NSArray arrayWithObject:@"valueClassName"] triggerChangeNotificationsForDependentKey:@"internalType"];
	}
	return;
}


#pragma mark Life cycle
- (id) initForClassDescription:(MCPClassDescription *) iClassDescription withName:(NSString *) iName
{
	self = [super init];
	{
		classDescription = iClassDescription;
		[self setName:iName];
//		relations = (NSMutableArray *)(CFArrayCreateMutable (kCFAllocatorDefault, 0, NULL));
		joins = [[NSMutableArray alloc] init];
	//	NSLog(@"MAKING a new object : %@", self);
	}
	return self;
}

- (void) dealloc
{
//	NSArray           *theRelations;
//	unsigned int      i;

//	NSLog(@"DEALLOCATING object : %@", self);
	[name release];
	[internalType release];
	[externalName release];
	[externalType release];
	[defaultValue release];
/*
	while ([relations count]) {
		[(MCPRelation *)[relations objectAtIndex:0] unjoinAttribute:self];
	}
// By now relation should be empty anyway...
	[relations release];
 */
	while ([joins count]) {
		[[self objectInJoinsAtIndex:0] invalidate];
	}
	// By now the joins array should be empty
	[joins release];
	[super dealloc];
}


#pragma mark NSCoding protocol
- (id) initWithCoder:(NSCoder *) decoder
{
	self = [super init];
	if ((self) && ([decoder allowsKeyedCoding])) {
		NSString    *theClassName = [decoder decodeObjectForKey:@"MCPvalueClassName"];
		
		classDescription = [decoder decodeObjectForKey:@"MCPclassDescription"];
		[self setName:[decoder decodeObjectForKey:@"MCPname"]];
		if (theClassName) {
			[self setValueClass:NSClassFromString(theClassName)];
		}
		[self setInternalType:[decoder decodeObjectForKey:@"MCPinternalType"]];
		[self setExternalName:[decoder decodeObjectForKey:@"MCPexternalName"]];
		[self setExternalType:[decoder decodeObjectForKey:@"MCPexternalType"]];
		[self setWidth:(unsigned int)[decoder decodeInt32ForKey:@"MCPwidth"]];
		[self setAllowsNull:[decoder decodeBoolForKey:@"MCPallowsNull"]];
		[self setAutoGenerated:[decoder decodeBoolForKey:@"MCPautoGenerated"]];
		[self setIsPartOfKey:[decoder decodeBoolForKey:@"MCPisPartOfKey"]];
		[self setIsPartOfIdentity:[decoder decodeBoolForKey:@"MCPisPartOfIdentity"]];
		[self setHasAccessor:[decoder decodeBoolForKey:@"MCPhasAccessor"]];
		[self setDefaultValue:[decoder decodeObjectForKey:@"MCPdefaultValue"]];
// Not sure that the next line is working (getting an array holding weak references), hence doing the thing expelcitly:
//      relations = [[decoder decodeObjectForKey:@"MCPrelations"] retain];
//		relations = (NSMutableArray *)(CFArrayCreateMutable (kCFAllocatorDefault, 0, NULL));
//		[relations addObjectsFromArray:[decoder decodeObjectForKey:@"MCPrelations"]];
		joins = [[NSMutableArray alloc] init]; // Will be filled in when the relations are read in.
	}
	else {
		NSLog(@"For some reason, unable to decode MCPAttribute from the coder!!!");
	}
//	NSLog(@"MAKING a new object : %@", self);
	return self;
}

- (void) encodeWithCoder:(NSCoder *) encoder
{
	NSString    *theValueClassName;
	
	if (! [encoder allowsKeyedCoding]) {
		NSLog(@"In MCPAttribute -encodeWithCoder : Unable to encode to a non-keyed encoder!!, will not perform encoding!!");
		return;
	}
//	theValueClassName = (valueClass) ? [valueClass className] : nil;
	theValueClassName = (valueClass) ? NSStringFromClass(valueClass) : nil;
	[encoder encodeObject:[self classDescription] forKey:@"MCPclassDescription"];
	[encoder encodeObject:[self name] forKey:@"MCPname"];
	if (theValueClassName) {
		[encoder encodeObject:theValueClassName forKey:@"MCPvalueClassName"];
	}
	[encoder encodeObject:[self internalType] forKey:@"MCPinternalType"];
	[encoder encodeObject:[self externalName] forKey:@"MCPexternalName"];
	[encoder encodeObject:[self externalType] forKey:@"MCPexternalType"];
	[encoder encodeInt32:(int32_t)[self width] forKey:@"MCPwidth"];
	[encoder encodeBool:[self allowsNull] forKey:@"MCPallowsNull"];
	[encoder encodeBool:[self autoGenerated] forKey:@"MCPautoGenerated"];
	[encoder encodeBool:[self isPartOfKey] forKey:@"MCPisPartOfKey"];
	[encoder encodeBool:[self isPartOfIdentity] forKey:@"MCPisPartOfIdentity"];
	[encoder encodeBool:[self hasAccessor] forKey:@"MCPhasAccessor"];
	[encoder encodeObject:[self defaultValue] forKey:@"MCPdefaultValue"];
//	[encoder encodeObject:relations forKey:@"MCPrelation"];
	// We don't have to save the joins here ... the joins are saving there attributes.
	// The links are recreated when the joins are decoded.
}

#pragma mark Setters
- (void) setName:(NSString *) iName
{
	if (iName != name) {
		[name release];
		name = [iName retain];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPModelChangedNotification object:[classDescription model]];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPClassDescriptionChangedNotification object:classDescription];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPAttributeChangedNotification object:self];
	}
}

- (void) setValueClass:(Class) iValueClass
{
	if (iValueClass != valueClass) {
		valueClass = iValueClass;
		if (valueClass) { // Not nil : set the internalType accrodingly.
								//         [internalType release];
								//         internalType = [[valueClass className] copy];
//			[self setValue:[NSString stringWithString:[valueClass className]] forKey:@"internalType"];
			[self setValue:[NSString stringWithString:NSStringFromClass(valueClass)] forKey:@"internalType"];
		}
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPModelChangedNotification object:[classDescription model]];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPClassDescriptionChangedNotification object:classDescription];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPAttributeChangedNotification object:self];
	}
#warning Should be coupled with the internal type, and the external type
}

- (void) setInternalType:(NSString *) iInternalType
{   
	if (iInternalType != internalType) {
		[internalType release];
		internalType = [iInternalType retain];
		if ([MCPRecognisedInternalType containsObject:internalType]) {
			[self setValueClass:NSClassFromString(internalType)];
//         By itself does NOT provide observers the update.
//         but see setKeys:triggerChangeNotificationsForDependentKey... (in +initialize).
		}
		else {
			[self setValueClass:nil];
		}
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPModelChangedNotification object:[classDescription model]];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPClassDescriptionChangedNotification object:classDescription];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPAttributeChangedNotification object:self];
	}
#warning Should be coupled with the value class, and the external type
}

- (void) setExternalType:(NSString *) iExternalType
{
	if (iExternalType != externalType) {
		[externalType release];
		externalType = [iExternalType retain];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPModelChangedNotification object:[classDescription model]];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPClassDescriptionChangedNotification object:classDescription];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPAttributeChangedNotification object:self];
	}
#warning Should be coupled with the internal type, and the value class
}

- (void) setExternalName:(NSString *) iExternalName
{
	if (iExternalName != externalName) {
		[externalName release];
		externalName = [iExternalName retain];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPModelChangedNotification object:[classDescription model]];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPClassDescriptionChangedNotification object:classDescription];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPAttributeChangedNotification object:self];
	}
}

- (void) setWidth:(unsigned int) iWidth
{
	if (iWidth != width) {
		width = iWidth;
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPModelChangedNotification object:[classDescription model]];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPClassDescriptionChangedNotification object:classDescription];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPAttributeChangedNotification object:self];
	}
}

- (void) setAllowsNull:(BOOL) iAllowsNull
{
	if (iAllowsNull != allowsNull) {
		allowsNull = iAllowsNull;
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPModelChangedNotification object:[classDescription model]];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPClassDescriptionChangedNotification object:classDescription];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPAttributeChangedNotification object:self];
	}
}

- (void) setAutoGenerated:(BOOL) iAutoGenerated
{
	if (iAutoGenerated != autoGenerated) {
		autoGenerated = iAutoGenerated;
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPModelChangedNotification object:[classDescription model]];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPClassDescriptionChangedNotification object:classDescription];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPAttributeChangedNotification object:self];
	}
}

- (void) setIsPartOfKey:(BOOL) iIsPartOfKey
{
	if (iIsPartOfKey != isPartOfKey) {
		isPartOfKey = iIsPartOfKey;
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPModelChangedNotification object:[classDescription model]];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPClassDescriptionChangedNotification object:classDescription];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPAttributeChangedNotification object:self];
	}
}

- (void) setIsPartOfIdentity:(BOOL) iIsPartOfIdentity
{
	if (iIsPartOfIdentity != isPartOfIdentity) {
		isPartOfIdentity = iIsPartOfIdentity;
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPModelChangedNotification object:[classDescription model]];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPClassDescriptionChangedNotification object:classDescription];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPAttributeChangedNotification object:self];
	}
}

- (void) setHasAccessor:(BOOL) iHasAccessor
{
	if (iHasAccessor != hasAccessor) {
		hasAccessor = iHasAccessor;
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPModelChangedNotification object:[classDescription model]];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPClassDescriptionChangedNotification object:classDescription];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPAttributeChangedNotification object:self];
	}
}

- (void) setDefaultValue:(id) iDefaultValue
{
	if (iDefaultValue != defaultValue) {
		[defaultValue release];
		defaultValue = [iDefaultValue retain];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPModelChangedNotification object:[classDescription model]];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPClassDescriptionChangedNotification object:classDescription];
		[[NSNotificationCenter defaultCenter] postNotificationName:MCPAttributeChangedNotification object:self];
	}
}

- (void) insertObject:(MCPJoin *) iJoin inJoinsAtIndex:(unsigned int) index
{
	[joins insertObject:iJoin atIndex:index];
}

- (void) removeObjectFromJoinsAtIndex:(unsigned int) index
{
	[joins removeObjectAtIndex:index];
}

/*
- (void) addRelation:(MCPRelation *) iRelation
{
// Following implementation make sure that a given relation is only added once... but I don't see the reason for that to be true.
	/*   if (NSNotFound == [relations indexOfObjectIdenticalTo:iRelation]) {
	[relations addObject:iRelation];
	}
	*//*
	[relations addObject:iRelation];
}

- (void) removeRelation:(MCPRelation *) iRelation
{
// Following implementation needs only one reference to a given relation to be working properly (not true)
//   [relations removeObjectIdenticalTo:iRelation];
	unsigned int      i;
	
	i = [relations indexOfObjectIdenticalTo:iRelation];
	if (NSNotFound != i) {
		[relations removeObjectAtIndex:i];
	}
// If the relation is there more than once, remove it only once.
}
*/

#pragma mark Getters
- (MCPClassDescription *) classDescription
{
	return classDescription;
}

- (NSString *) name
{
	return name;
}

- (Class) valueClass
{
	return valueClass;
}

- (NSString *) valueClassName
{
	return NSStringFromClass(valueClass);
//	return [valueClass className];
}

- (NSString *) internalType
{
	return internalType;
}

- (NSString *) externalName
{
	return externalName;
}

- (NSString *) externalType
{
	return externalType;
}

- (unsigned int) width
{
	return width;
}

- (BOOL) allowsNull
{
	return allowsNull;
}

- (BOOL) autoGenerated
{
	return autoGenerated;
}

- (BOOL) isPartOfKey
{
	return isPartOfKey;
}

- (BOOL) isPartOfIdentity
{
	return isPartOfIdentity;
}

- (BOOL) hasAccessor
{
	return hasAccessor;
}

- (id) defaultValue
{
	return defaultValue;
}

- (unsigned int) countOfJoins
{
	return [joins count];
}

- (MCPJoin *) objectInJoinsAtIndex:(unsigned int) index
{
	return (MCPJoin *)((NSNotFound != index) ? [joins objectAtIndex:index] : nil);
}

- (unsigned int) indexOfJoinIdenticalTo:(id) iJoin
{
	return [joins indexOfObjectIdenticalTo:iJoin];
}

#pragma mark Some general methods:
- (BOOL) isEqual:(id) iObject
// Equal to another attribute, if they have the same name and same class description.
// Equal to a string (NSString), if the name of the attribute is equal to the string.
{
	if ([iObject isKindOfClass:[MCPAttribute class]]) {
		MCPAttribute    *theAttribute = (MCPAttribute *) iObject;
		
		return ([name isEqualToString:[theAttribute name]]) && ([classDescription isEqual:[theAttribute classDescription]]);
	}
	if ([iObject isKindOfClass:[NSString class]]) {
		return [name isEqualToString:(NSString *)iObject];
	}
	return NO;
}

#pragma mark For debugging the retain counting
- (id) retain
{
	[super retain];
//	NSLog(@"in -[MCPAttribute retain] for %@, count is %u (after retain).", self, [self retainCount]);
	return self;
}

- (void) release
{
//	NSLog(@"in -[MCPAttribute release] for %@, count is %u (after release).", self, [self retainCount]-1);
	[super release];
	return;
}

@end

@implementation MCPAttribute (Private)

- (void)setValueClassName:(NSString *) iClassName
{
	if (NSClassFromString(iClassName) != valueClass) {
		[self setValueClass:NSClassFromString(iClassName)];    
	}
}

@end
