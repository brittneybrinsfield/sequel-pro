//
//  $Id: FLXPostgresConnectionQueryExecution.h 3793 2012-09-03 10:22:17Z stuart02 $
//
//  FLXPostgresConnectionQueryExecution.h
//  PostgresKit
//
//  Copyright (c) 2008-2009 David Thorpe, djt@mutablelogic.com
//
//  Forked by the Sequel Pro Team on July 22, 2012.
// 
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not 
//  use this file except in compliance with the License. You may obtain a copy of 
//  the License at
// 
//  http://www.apache.org/licenses/LICENSE-2.0
// 
//  Unless required by applicable law or agreed to in writing, software 
//  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT 
//  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the 
//  License for the specific language governing permissions and limitations under
//  the License.

#import "FLXPostgresConnection.h"

@interface FLXPostgresConnection (FLXPostgresConnectionQueryExecution)

// Synchronous interface
- (FLXPostgresResult *)execute:(NSString *)query;
- (FLXPostgresResult *)executeWithFormat:(NSString *)query, ...;
- (FLXPostgresResult *)executePrepared:(FLXPostgresStatement *)statement;
- (FLXPostgresResult *)execute:(NSString *)query values:(NSArray *)values;
- (FLXPostgresResult *)execute:(NSString *)query value:(NSObject *)value;
- (FLXPostgresResult *)executePrepared:(FLXPostgresStatement *)statement values:(NSArray *)values;
- (FLXPostgresResult *)executePrepared:(FLXPostgresStatement *)statement value:(NSObject *)value;

// Asynchronous interface

@end