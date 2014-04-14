/*
 *
 * Copyright 2014 Flavio Negrão Torres
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


@import XCTest;
@import CoreData;
@import AVFoundation;

#import <Parse/Parse.h>
#import "APParseConnector.h"

#import "NSLogEmoji.h"
#import "Common.h"
#import "APError.h"

#import "Author.h"
#import "Book.h"
#import "Page.h"

#import "UnitTestingCommon.h"

/* Parse objects strings */
static NSString* const kAuthorNameParse = @"George R. R. Martin";
static NSString* const kBookNameParse1 = @"A Game of Thrones";
static NSString* const kBookNameParse2 = @"A Clash of Kings";
static NSString* const kBookNameParse3 = @"A Storm of Swords";
static NSString* const kBookNameParse4 = @"A Feast for Crows";

/* Local objects strings */
static NSString* const kAuthorNameLocal = @"J. R. R. Tolkien";
static NSString* const kBookNameLocal1 = @"The Fellowship of the Ring";
static NSString* const kBookNameLocal2 = @"The Two Towers";
static NSString* const kBookNameLocal3 = @"The Return of the King";

/* Test core data persistant store file name */
static NSString* const testSqliteFile = @"APParseConnectorTestFile.sqlite";


@interface APParseConnectorTestCase : XCTestCase

@property (strong, nonatomic) NSManagedObjectModel* testModel;
@property (strong, nonatomic) NSManagedObjectContext* testContext;
@property (strong, nonatomic) dispatch_queue_t queue;
@property (strong, nonatomic) dispatch_group_t group;
@property (strong, nonatomic) APParseConnector* parseConnector;

@end


@implementation APParseConnectorTestCase

#pragma mark - Set up

- (void)setUp {
    
    MLog();
    
    [super setUp];
    DLog(@"---------Setting up the test environement----------");
    
    // Remove SQLite file
    [self removeCacheStore];
    
    /* 
     All tests will be conducted in background to enable us to supress the *$@%@$ Parse SDK warning
     complening that we are running long calls in the main thread.
     */
    self.queue = dispatch_queue_create("parseConnectorTestCase", NULL);
    self.group = dispatch_group_create();
    
    [Parse setApplicationId:APUnitTestingParsepApplicationId clientKey:APUnitTestingParseClientKey];
    
    dispatch_group_async(self.group, self.queue, ^{
        
        PFUser* authenticatedUser = [PFUser logInWithUsername:APUnitTestingParseUserName password:APUnitTestingParsePassword];
        if (!authenticatedUser){
            ELog(@"User is authenticated, check credentials");
        } else {
            DLog(@"User has been authenticated:%@",authenticatedUser.username);
        }
        self.parseConnector = [[APParseConnector alloc]initWithAuthenticatedUser:authenticatedUser mergePolicy:APMergePolicyClientWins];
        
        [self removeAllEntriesFromParse];
        NSError* saveError = nil;
        
        /*
         Create Parse Objects and their relationships
         
         ----------       --------
         | Author |<---->>| Book |
         ----------       --------
         
         */
        
        PFObject* book1 = [PFObject objectWithClassName:@"Book"];
        [book1 setValue:kBookNameParse1 forKey:@"name"];
        [book1 setValue:@NO forKey:APObjectIsDeletedAttributeName];
        [book1 save:&saveError];
        DLog(@"Book %@ has been created",kBookNameParse1);
        
        PFObject* book2 = [PFObject objectWithClassName:@"Book"];
        [book2 setValue:kBookNameParse2 forKey:@"name"];
        [book2 setValue:@NO forKey:APObjectIsDeletedAttributeName];
        [book2 save:&saveError];
        DLog(@"Book %@ has been created",kBookNameParse2);
        
        PFObject* author = [PFObject objectWithClassName:@"Author"];
        [author setValue:kAuthorNameParse forKey:@"name"];
        [author setValue:@NO forKey:APObjectIsDeletedAttributeName];
        [author save:&saveError];
        DLog(@"Author %@ has been created",kAuthorNameParse);
        
        // Relation (To-Many)
        [[author relationForKey:@"books"] addObject:book1];
        [[author relationForKey:@"books"] addObject:book2];
        [author save:&saveError];
        
        // Pointer (To-One)
        book1[@"author"] = author;
        [book1 save:&saveError];
        book2[@"author"] = author;
        [book2 save:&saveError];

        DLog(@"Relations have been set");
    });
    dispatch_group_wait(self.group, DISPATCH_TIME_FOREVER);
    DLog(@"------------Test environement ready!----------------");
}


- (void) tearDown {
    
    DLog(@"-----------Removing Test environement-------------");
    self.testContext = nil;
    
    // Remove SQLite file
    [self removeCacheStore];
    
    dispatch_group_async(self.group, self.queue, ^{
        [self removeAllEntriesFromParse];
    });
    dispatch_group_wait(self.group, DISPATCH_TIME_FOREVER);
    DLog(@"------Test environement has been decomissioned-----");
    [super tearDown];
}


#pragma mark - Tests - Basic Stuff

- (void) testTestContextIsSet {
    
    XCTAssertNotNil(self.testContext);
}


#pragma mark  - Tests - Objects created remotely

- (void) testMergeRemoteObjects {
    
    __block NSArray* results;
    __block NSError* syncError;
    
    dispatch_group_async(self.group, self.queue, ^{
        results = [self.parseConnector mergeRemoteObjectsWithContext:self.testContext fullSync:YES onSyncObject:^{
            DLog(@"Object has been synced");
        } error:&syncError];
    });
    dispatch_group_wait(self.group, DISPATCH_TIME_FOREVER);
    
    XCTAssertNil(syncError, @"Sync error:%@",syncError);
    XCTAssertTrue([results count] == 3);
    
    NSFetchRequest* booksFr = [NSFetchRequest fetchRequestWithEntityName:@"Book"];
    booksFr.predicate = [NSPredicate predicateWithFormat:@"name == %@",kBookNameParse1];
    NSArray* books = [self.testContext executeFetchRequest:booksFr error:nil];
    Book* book = [books lastObject];
    XCTAssertNotNil(book);
    
    NSFetchRequest* authorFr = [NSFetchRequest fetchRequestWithEntityName:@"Author"];
    booksFr.predicate = [NSPredicate predicateWithFormat:@"name == %@",kAuthorNameParse];
    NSArray* authors = [self.testContext executeFetchRequest:authorFr error:nil];
    Author* author = [authors lastObject];
    XCTAssertNotNil(author);
}


- (void) testMergeRemoteCreatedRelationshipToOne {
    
    __block NSArray* results;
    __block NSError* syncError;
    
    dispatch_group_async(self.group, self.queue, ^{
        results = [self.parseConnector mergeRemoteObjectsWithContext:self.testContext fullSync:YES onSyncObject:^{
            DLog(@"Object has been synced");
        } error:&syncError];

    });
    dispatch_group_wait(self.group, DISPATCH_TIME_FOREVER);
    
    NSFetchRequest* booksFr = [NSFetchRequest fetchRequestWithEntityName:@"Book"];
    NSArray* books = [self.testContext executeFetchRequest:booksFr error:nil];
    Book* book = [books lastObject];
    XCTAssertEqualObjects(book.author.name, kAuthorNameParse);
}


- (void) testMergeRemoteCreatedRelationshipToMany {
    
    __block NSArray* results;
    __block NSError* syncError;
    
    dispatch_group_async(self.group, self.queue, ^{
        results = [self.parseConnector mergeRemoteObjectsWithContext:self.testContext fullSync:YES onSyncObject:^{
            DLog(@"Object has been synced");
        } error:&syncError];

    });
    dispatch_group_wait(self.group, DISPATCH_TIME_FOREVER);
    
    NSFetchRequest* authorFr = [NSFetchRequest fetchRequestWithEntityName:@"Author"];
    NSArray* authors = [self.testContext executeFetchRequest:authorFr error:nil];
    Author* author = [authors lastObject];
    XCTAssert([author.books count] == 2);
    
    Book* relatedBook1 = [[[author.books allObjects] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name == %@",kBookNameParse1]]lastObject];
    XCTAssertNotNil(relatedBook1);
    
    Book* relatedBook2 = [[[author.books allObjects] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name == %@",kBookNameParse2]]lastObject];
    XCTAssertNotNil(relatedBook2);
}


#pragma mark  - Tests - Objects deleted remotely

- (void) testMergeRemoteDeletedObjects {
    
    dispatch_group_async(self.group, self.queue, ^{
        
        // Merge server objects
        NSError* error;
        [self.parseConnector mergeRemoteObjectsWithContext:self.testContext fullSync:YES onSyncObject:^{
            DLog(@"Object has been synced");
        } error:&error];

        XCTAssertNil(error);
        
        // Mark Author as deleted
        PFQuery* authorQuery = [PFQuery queryWithClassName:@"Author"];
        [authorQuery whereKey:@"name" containsString:kAuthorNameParse];
        PFObject* parseAuthor = [[authorQuery findObjects]lastObject];
        [parseAuthor setValue:@YES forKey:APObjectIsDeletedAttributeName];
        [parseAuthor save:&error];
        XCTAssertNil(error);
        
        [self.parseConnector mergeRemoteObjectsWithContext:self.testContext fullSync:YES onSyncObject:^{
            DLog(@"Object has been synced");
        } error:&error];
        
        // Fetch local object
        NSFetchRequest* authorFr = [NSFetchRequest fetchRequestWithEntityName:@"Author"];
        authorFr.predicate = [NSPredicate predicateWithFormat:@"name == %@",kAuthorNameParse];
        NSArray* authors = [self.testContext executeFetchRequest:authorFr error:nil];
        XCTAssertTrue([authors count] == 0);
    });
    dispatch_group_wait(self.group, DISPATCH_TIME_FOREVER);
    
}


#pragma mark  - Tests - Objects created locally

- (void) testMergeLocalCreatedObjects {
    
    dispatch_group_async(self.group, self.queue, ^{
        __block NSError* mergeError;
        
        // Create a local Book and insert it on Parse
        Book* book = [NSEntityDescription insertNewObjectForEntityForName:@"Book" inManagedObjectContext:self.testContext];
        [book setValue:@YES forKey:APObjectIsDirtyAttributeName];
        [book setValue:APObjectTemporaryUIDPrefix forKey:APObjectUIDAttributeName];
        book.name = kBookNameLocal1;
        
        // Create a local Author and insert it on Parse
        Author* author = [NSEntityDescription insertNewObjectForEntityForName:@"Author" inManagedObjectContext:self.testContext];
        [author setValue:@YES forKey:APObjectIsDirtyAttributeName];
        [author setValue:APObjectTemporaryUIDPrefix forKey:APObjectUIDAttributeName];
        author.name =kAuthorNameLocal;
        
        // Ensure that both objects have the temp prefix set on their objectUID property
        XCTAssertTrue([[book valueForKey:APObjectUIDAttributeName]hasPrefix:APObjectTemporaryUIDPrefix]);
        XCTAssertTrue([[author valueForKey:APObjectUIDAttributeName]hasPrefix:APObjectTemporaryUIDPrefix]);
        
        [self.parseConnector mergeManagedContext:self.testContext onSyncObject:^{
            DLog(@"Object has been synced");
        } error:&mergeError];
        
        // Ensure that both objects has their temp prefix removed from the objectUID property
        XCTAssertFalse([[book valueForKey:APObjectUIDAttributeName]hasPrefix:APObjectTemporaryUIDPrefix]);
        XCTAssertFalse([[author valueForKey:APObjectUIDAttributeName]hasPrefix:APObjectTemporaryUIDPrefix]);
        
        PFQuery* bookQuery = [PFQuery queryWithClassName:@"Book"];
        [bookQuery whereKey:@"name" containsString:kBookNameLocal1];
        PFObject* fetchedBook;
        fetchedBook = [[bookQuery findObjects]lastObject];
        
        XCTAssertNotNil(fetchedBook);
        XCTAssertEqualObjects([fetchedBook valueForKey:@"name"],kBookNameLocal1);
    });
    
    dispatch_group_wait(self.group, DISPATCH_TIME_FOREVER);
}

- (void) testMergeLocalCreatedRelationshipToOne {
    
    dispatch_group_async(self.group, self.queue, ^{
        __block NSError* mergeError;
        
        // Create a local Book, mark is as "dirty" and set the objectUID with the predefined prefix
        Book* book = [NSEntityDescription insertNewObjectForEntityForName:@"Book" inManagedObjectContext:self.testContext];
        [book setValue:@YES forKey:APObjectIsDirtyAttributeName];
        [book setValue:APObjectTemporaryUIDPrefix forKey:APObjectUIDAttributeName];
        book.name = kBookNameLocal1;
        
        // Create a local Author, mark is as "dirty" and set the objectUID with the predefined prefix
        Author* author = [NSEntityDescription insertNewObjectForEntityForName:@"Author" inManagedObjectContext:self.testContext];
        [author setValue:@YES forKey:APObjectIsDirtyAttributeName];
        [author setValue:APObjectTemporaryUIDPrefix forKey:APObjectUIDAttributeName];
        author.name =kAuthorNameLocal;

        // Create the relationship locally and merge the context with Parse
        book.author = author;
        [self.parseConnector mergeManagedContext:self.testContext onSyncObject:^{
            DLog(@"Object has been synced");
        } error:&mergeError];
        
        // Fetch the book from Parse and verify the related To-One author
        PFQuery* bookQuery = [PFQuery queryWithClassName:@"Book"];
        [bookQuery whereKey:@"name" containsString:kBookNameLocal1];
        PFObject* fetchedBook;
        fetchedBook = [[bookQuery findObjects]lastObject];
        PFObject* relatedAuthor = fetchedBook[@"author"];
        [relatedAuthor refresh];
        
        XCTAssertNotNil(relatedAuthor);
        XCTAssertEqualObjects([relatedAuthor valueForKey:@"name"],kAuthorNameLocal);
    });
    
    dispatch_group_wait(self.group, DISPATCH_TIME_FOREVER);
}


/*
 Scenario:
 - Create 2x books locally
 - Create a author locally and associate both books to it.
 - Next we merge with our managed context
 
 Expected Results:
 - We fetch from Parse the created author and its relationship to books
 - Both books should be related to the author.
 */
- (void) testMergeLocalCreatedRelationshipToMany {
    
    dispatch_group_async(self.group, self.queue, ^{
        __block NSError* mergeError;
        
        // Create a local Book, mark is as "dirty" and set the objectUID with the predefined prefix
        Book* book1 = [NSEntityDescription insertNewObjectForEntityForName:@"Book" inManagedObjectContext:self.testContext];
        [book1 setValue:@YES forKey:APObjectIsDirtyAttributeName];
        [book1 setValue:APObjectTemporaryUIDPrefix forKey:APObjectUIDAttributeName];
        book1.name = kBookNameLocal1;
        
        // Create a local Book, mark is as "dirty" and set the objectUID with the predefined prefix
        Book* book2 = [NSEntityDescription insertNewObjectForEntityForName:@"Book" inManagedObjectContext:self.testContext];
        [book2 setValue:@YES forKey:APObjectIsDirtyAttributeName];
        [book2 setValue:APObjectTemporaryUIDPrefix forKey:APObjectUIDAttributeName];
        book2.name = kBookNameLocal2;
        
        // Create a local Author, mark is as "dirty" and set the objectUID with the predefined prefix
        Author* author = [NSEntityDescription insertNewObjectForEntityForName:@"Author" inManagedObjectContext:self.testContext];
        [author setValue:@YES forKey:APObjectIsDirtyAttributeName];
        [author setValue:APObjectTemporaryUIDPrefix forKey:APObjectUIDAttributeName];
        author.name =kAuthorNameLocal;
        
        // Create the relationship locally and merge the context with Parse
        [author addBooksObject:book1];
        [author addBooksObject:book2];
        [self.parseConnector mergeManagedContext:self.testContext onSyncObject:^{
            DLog(@"Object has been synced");
        } error:&mergeError];
        
        // Fetch the book from Parse and verify the related To-One author
        PFQuery* authorQuery = [PFQuery queryWithClassName:@"Author"];
        [authorQuery whereKey:@"name" containsString:kAuthorNameLocal];
        PFObject* fetchedAuthor = [[authorQuery findObjects]lastObject];
        
        PFRelation* booksRelation = [fetchedAuthor relationForKey:@"books"];
        NSArray* books = [[booksRelation query]findObjects];
        XCTAssertTrue([books count] == 2);
        
        Book* relatedBook1 = [[books filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name == %@",kBookNameLocal1]]lastObject];
        XCTAssertNotNil(relatedBook1);
        
        Book* relatedBook2 = [[books filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name == %@",kBookNameLocal1]]lastObject];
        XCTAssertNotNil(relatedBook2);
    });
    
    dispatch_group_wait(self.group, DISPATCH_TIME_FOREVER);
}

#pragma mark - Tests - Binary Attributes

/*
 Scenario:
 - We are going to get a image from the Internet and set a parse object book attribute "picture" with it.
 - Next we merge with our managed context
 
 Expected Results:
 - The same image should be present in the equivalement local core data book.
 */
- (void) testBinaryAttributeMergingFromParse {
    
    dispatch_group_async(self.group, self.queue, ^{
        
        // 495KB JPG Image sample image
        NSURL *imageURL = [[[NSBundle mainBundle]bundleURL] URLByAppendingPathComponent:@"Sample_495KB.jpg"];
        NSData* bookCoverData = [NSData dataWithContentsOfURL:imageURL];
        XCTAssertNotNil(bookCoverData);
        
        NSError* savingError;
        PFFile* bookCoverFile = [PFFile fileWithData:bookCoverData];
        XCTAssertTrue([bookCoverFile save:&savingError]);
        XCTAssertNil(savingError);
        
        PFQuery* bookQuery = [PFQuery queryWithClassName:@"Book"];
        [bookQuery whereKey:@"name" containsString:kBookNameParse1];
        PFObject* fetchedBookFromParse = [[bookQuery findObjects]lastObject];
        XCTAssertNotNil(fetchedBookFromParse);
        
        fetchedBookFromParse[@"picture"] = bookCoverFile;
        XCTAssertTrue([fetchedBookFromParse save:&savingError]);
        XCTAssertNil(savingError);
        
        NSError* mergeError;
        [self.parseConnector mergeRemoteObjectsWithContext:self.testContext fullSync:YES onSyncObject:^{
            DLog(@"Object has been synced");
        } error:&mergeError];
        XCTAssertNil(mergeError);
        
        NSFetchRequest* booksFr = [NSFetchRequest fetchRequestWithEntityName:@"Book"];
        booksFr.predicate = [NSPredicate predicateWithFormat:@"name == %@",kBookNameParse1];
        NSArray* books = [self.testContext executeFetchRequest:booksFr error:nil];
        Book* book = [books lastObject];
        XCTAssertNotNil(book);
        XCTAssertTrue([bookCoverData isEqualToData:book.picture]);
    });
    
    dispatch_group_wait(self.group, DISPATCH_TIME_FOREVER);
}

/*
 Scenario:
 - We are going to get a image from the Internet and set a local managed object book attribute "picture" with it.
 - Next we merge with our managed context into Parse
 
 Expected Results:
 - The same image should be present in the equivalement parse object book.
 */
- (void) testBinaryAttributeMergingToParse {
    
    dispatch_group_async(self.group, self.queue, ^{
        
        NSError* mergeError;
        [self.parseConnector mergeRemoteObjectsWithContext:self.testContext fullSync:YES onSyncObject:^{
            DLog(@"Object has been synced");
        } error:&mergeError];
        XCTAssertNil(mergeError);
        
        NSFetchRequest* booksFr = [NSFetchRequest fetchRequestWithEntityName:@"Book"];
        booksFr.predicate = [NSPredicate predicateWithFormat:@"name == %@",kBookNameParse1];
        NSArray* books = [self.testContext executeFetchRequest:booksFr error:nil];
        Book* book = [books lastObject];
        XCTAssertNotNil(book);
        
        // 495KB JPG Image sample image
        NSURL *imageURL = [[[NSBundle mainBundle]bundleURL] URLByAppendingPathComponent:@"Sample_495KB.jpg"];
        NSData* bookCoverData = [NSData dataWithContentsOfURL:imageURL];
        XCTAssertNotNil(bookCoverData);
        
        book.picture = bookCoverData;
        [book setValue:@YES forKey:APObjectIsDirtyAttributeName];
       
        NSError* saveError;
        [self.testContext save:&saveError];
        XCTAssertNil(saveError);
        
        [self.parseConnector mergeManagedContext:self.testContext onSyncObject:^{
            DLog(@"Object has been synced");
        } error:&mergeError];
        XCTAssertNil(mergeError);
        
        PFQuery* bookQuery = [PFQuery queryWithClassName:@"Book"];
        [bookQuery whereKey:@"name" containsString:kBookNameParse1];
        PFObject* fetchedBook = [[bookQuery findObjects]lastObject];
        XCTAssertNotNil(fetchedBook);
        
        PFFile* pictureFromParse = [fetchedBook objectForKey:@"picture"];
        NSData* parseBookCoverData = [pictureFromParse getData];
        XCTAssertNotNil(parseBookCoverData);
        
        XCTAssertTrue([parseBookCoverData isEqualToData:bookCoverData]);
    });
    
    dispatch_group_wait(self.group, DISPATCH_TIME_FOREVER);
}


#pragma mark  - Tests - Conflicts

/*
 Scenario:  
 - We merge an existing object from Parse that wasn't localy present before
 - Therefore the local kAPIncrementalStoreLastModifiedAttributeName gets populated.
 - The same object gets changed at Parse again consequentely updatedAt gets updated as well.
 
Expected Results:
 - The local kAPIncrementalStoreLastModifiedAttributeName should get the new date.
 */
- (void) testModifiedDatesAfterMergeFromServer {
    
    dispatch_group_async(self.group, self.queue, ^{
        
        // Sync server objects
        NSError* mergeError;
        [self.parseConnector mergeRemoteObjectsWithContext:self.testContext fullSync:YES onSyncObject:^{
            DLog(@"Object has been synced");
        } error:&mergeError];
        XCTAssertNil(mergeError);
        
        // Fetch local object
        NSFetchRequest* booksFr = [NSFetchRequest fetchRequestWithEntityName:@"Book"];
        booksFr.predicate = [NSPredicate predicateWithFormat:@"name == %@",kBookNameParse1];
        NSArray* books = [self.testContext executeFetchRequest:booksFr error:nil];
        Book* localBook = [books lastObject];
        
        NSDate* originalDate = [localBook valueForKey:APObjectLastModifiedAttributeName];
        XCTAssertNotNil(originalDate);
        
        PFQuery* bookQuery = [PFQuery queryWithClassName:@"Book"];
        [bookQuery whereKey:@"name" containsString:kBookNameParse1];
        PFObject* parseBook = [[bookQuery findObjects]lastObject];
        XCTAssertNotNil(parseBook);
        XCTAssertEqualObjects(parseBook.updatedAt, originalDate);
        
        [parseBook setValue:kBookNameParse2 forKey:@"name"];
        
        // Wait for 5 seconds and save the object
        [NSThread sleepForTimeInterval:5];
        [parseBook save];
        [self.parseConnector mergeRemoteObjectsWithContext:self.testContext fullSync:YES onSyncObject:^{
            DLog(@"Object has been synced");
        } error:&mergeError];
        
        // The local object date should have been updated.
        NSDate* updatedDate = [localBook valueForKey:APObjectLastModifiedAttributeName];
        XCTAssertTrue([updatedDate compare:originalDate] == NSOrderedDescending);
    });
    dispatch_group_wait(self.group, DISPATCH_TIME_FOREVER);
}


/*
 Scenario:  
 - We have merged our context, then we update an book name making it "dirty".
 - Before we merge it back to Parse, the remote equivalent object gets updated, characterizing a conflict.
            
 Expected Results:
 - As the policy is set to Client wins, the remote object gets overridden by the local object
 - Conflicts may only occur when we are merging local "dirty" objects.
 */
- (void) testConflictWhenMergingObjectsClientWinsPolicy {
    
    dispatch_group_async(self.group, self.queue, ^{
        
        [self.parseConnector setMergePolicy:APMergePolicyClientWins];
        
        // Sync server objects
        NSError* mergeError;
        [self.parseConnector mergeRemoteObjectsWithContext:self.testContext fullSync:YES onSyncObject:^{
            DLog(@"Object has been synced");
        } error:&mergeError];
        XCTAssertNil(mergeError);
        
        // Fetch local object
        NSFetchRequest* booksFr = [NSFetchRequest fetchRequestWithEntityName:@"Book"];
        booksFr.predicate = [NSPredicate predicateWithFormat:@"name == %@",kBookNameParse1];
        NSArray* books = [self.testContext executeFetchRequest:booksFr error:nil];
        Book* localBook = [books lastObject];
        localBook.name = kBookNameParse3;
        [localBook setValue:@YES forKey:APObjectIsDirtyAttributeName];
        
        //[NSThread sleepForTimeInterval:2];
        
        // Fetch, change the book name and save it back to Parse
        PFQuery* bookQuery = [PFQuery queryWithClassName:@"Book"];
        [bookQuery whereKey:@"name" containsString:kBookNameParse1];
        PFObject* parseBook = [[bookQuery findObjects]lastObject];
        [parseBook setValue:kBookNameParse4 forKey:@"name" ];
        [parseBook save:&mergeError];
        XCTAssertNil(mergeError);
        XCTAssertTrue([parseBook.objectId isEqualToString:[localBook valueForKey:APObjectUIDAttributeName]]);
        
        [self.parseConnector mergeManagedContext:self.testContext onSyncObject:^{
            DLog(@"Object has been synced");
        } error:&mergeError];
        XCTAssertNil(mergeError);
        XCTAssertEqualObjects(localBook.name, kBookNameParse3);
        
        [parseBook refresh];
        XCTAssertEqualObjects([parseBook valueForKey:@"name"], kBookNameParse3);
    });
        
    dispatch_group_wait(self.group, DISPATCH_TIME_FOREVER);
}


/*
 Scenario:
 - We have merged our context, then we update an book name making it "dirty".
 - Before we merge it back to Parse, the remote equivalent object gets updated, characterizing a conflict.
 
 Expected Results:
 - As the policy is set to Server wins, the local object gets overridden by the server object
 - Conflicts may only occur when we are merging local "dirty" objects.
 */
- (void) testConflictWhenMergingObjectsServerWinsPolicy {
    
    [self.parseConnector setMergePolicy:APMergePolicyServerWins];
    
    dispatch_group_async(self.group, self.queue, ^{
        
        // Sync server objects
        NSError* mergeError;
        
        [self.parseConnector mergeRemoteObjectsWithContext:self.testContext fullSync:YES onSyncObject:^{
            DLog(@"Object has been synced");
        } error:&mergeError];
        
        XCTAssertNil(mergeError);
        
        // Fetch local object
        NSFetchRequest* booksFr = [NSFetchRequest fetchRequestWithEntityName:@"Book"];
        booksFr.predicate = [NSPredicate predicateWithFormat:@"name == %@",kBookNameParse1];
        NSArray* books = [self.testContext executeFetchRequest:booksFr error:nil];
        Book* localBook = [books lastObject];
        localBook.name = kBookNameParse3;
        [localBook setValue:@YES forKey:APObjectIsDirtyAttributeName];
        
        // Fetch, change the book name and save it back to Parse
        PFQuery* bookQuery = [PFQuery queryWithClassName:@"Book"];
        [bookQuery whereKey:@"name" containsString:kBookNameParse1];
        PFObject* parseBook = [[bookQuery findObjects]lastObject];
        [parseBook setValue:kBookNameParse4 forKey:@"name" ];
        [parseBook save:&mergeError];
        XCTAssertNil(mergeError);
        XCTAssertTrue([parseBook.objectId isEqualToString:[localBook valueForKey:APObjectUIDAttributeName]]);

        [self.parseConnector mergeManagedContext:self.testContext onSyncObject:^{
            DLog(@"Object has been synced");
        } error:&mergeError];
        XCTAssertNil(mergeError);
        
        // Fetch local object
        NSFetchRequest* renamedBooksFr = [NSFetchRequest fetchRequestWithEntityName:@"Book"];
        renamedBooksFr.predicate = [NSPredicate predicateWithFormat:@"name == %@",kBookNameParse4];
        NSArray* remamedBooks = [self.testContext executeFetchRequest:renamedBooksFr error:nil];
        Book* localBookRenamed = [remamedBooks lastObject];
        XCTAssertEqualObjects(localBookRenamed.name, kBookNameParse4);
    });
    
    dispatch_group_wait(self.group, DISPATCH_TIME_FOREVER);
}


- (void) testParseUpdatedAtDates {
    
    dispatch_group_async(self.group, self.queue, ^{
        PFObject* book = [[PFObject alloc]initWithClassName:@"Book"];
        [book setValue:@"some name" forKeyPath:@"name"];
        [book save:nil];
        NSDate* updatedAtAfterSave = book.updatedAt;
        
        PFQuery* query = [PFQuery queryWithClassName:@"Book"];
        [query whereKey:@"name" containsString:@"some name"];
        PFObject* fetchedBook = [[query findObjects]lastObject];
        NSDate* updatedAtAfterFetch = fetchedBook.updatedAt;
        
        XCTAssertEqualObjects(updatedAtAfterSave, updatedAtAfterFetch);
    });
    
    dispatch_group_wait(self.group, DISPATCH_TIME_FOREVER);
}

/*
 This test is a bit trick to be executed as we need to change the localcache sync implementation in a way that we can pause it and change few objects at Parse.
 That change on parse object will simulate another client changing objects while we are syncing as well.
 The steps will be:
 1. Create the objects via -setUp
 2. Start the sync process and pause it for 10 seconds after all books have been received.
 3. While ithe sync process paused introduce a new book to the same initial author, so that it will not be synced during this sync loop.
 4. Sync again and the new book should be recevied.
 
 Don't forget to uncomment the changes included on APParceConnector to make this test possible.
 You can find it at the end of the method -[APParseConnector mergeRemoteObjectsWithContext:fullSync:error:]
 
 */

- (void) testMergingWithOtherClientMergingSimultaneously {
    
    // Sync server objects 1st time
//    NSError* mergeError;
//    [self.parseConnector mergeRemoteObjectsWithContext:self.testContext fullSync:NO error:&mergeError];
//    XCTAssertNil(mergeError);
//    
//    // Fetch local objects
//    NSFetchRequest* booksFr1 = [NSFetchRequest fetchRequestWithEntityName:@"Book"];
//    booksFr1.predicate = [NSPredicate predicateWithFormat:@"name == %@",@"another book"];
//    XCTAssertTrue([[self.testContext executeFetchRequest:booksFr1 error:nil] count] == 0);
//    
//    // Fetch local objects
//    NSFetchRequest* pageFr = [NSFetchRequest fetchRequestWithEntityName:@"Page"];
//    XCTAssertTrue([[self.testContext executeFetchRequest:pageFr error:nil] count] == 1);
//    
//    
//    // Sync server objects 2nd time
//    [self.parseConnector mergeRemoteObjectsWithContext:self.testContext fullSync:NO error:&mergeError];
//    XCTAssertNil(mergeError);
//    
//    // Fetch local object
//    NSFetchRequest* booksFr2= [NSFetchRequest fetchRequestWithEntityName:@"Book"];
//    booksFr2.predicate = [NSPredicate predicateWithFormat:@"name == %@",@"another book"];
//    XCTAssertTrue([[self.testContext executeFetchRequest:booksFr2 error:nil] count] == 1);
}


#pragma mark - Support Methods

- (void) removeAllEntriesFromParse {
    
    MLog();
    [self removeAllObjectsFromParseQuery:[PFQuery queryWithClassName:@"Author"]];
    [self removeAllObjectsFromParseQuery:[PFQuery queryWithClassName:@"Book"]];
    [self removeAllObjectsFromParseQuery:[PFQuery queryWithClassName:@"Page"]];
}


- (void) removeAllObjectsFromParseQuery:(PFQuery*) query {
    
    // Delete parse object block
    void (^deleteAllObjects)(PFObject*, NSUInteger, BOOL*) = ^(PFObject* obj, NSUInteger idx, BOOL *stop) {
        NSError* error;
        [obj delete:&error];
        if (!error) {
            DLog(@"Object of class: %@ was deleted from Parse",[obj parseClassName]);
        } else {
            ELog(@"Object of class: %@ was not deleted from Parse - error: %@",[obj parseClassName],error);
        }
    };
    
    // count how many objects we have to remove
    // default parse limit of objects per query is 100, can be set to 1000.
    // let's maintain the default.
    NSError* error;
    NSUInteger numberOfObjectsToDelete = [query countObjects:&error];
    if (error) {
        ELog(@"Error counting objects for query for class: %@",query.parseClassName);
        return;
    }
    
    NSUInteger const step = 100;
    NSUInteger deleted = 0;
    while (deleted < numberOfObjectsToDelete) {
        //[query setSkip:skip];
        [[query findObjects]enumerateObjectsUsingBlock:deleteAllObjects];
        deleted += step;
    }
}



- (NSManagedObjectModel*) testModel {
    
    if (!_testModel) {
        
        NSManagedObjectModel* model = [[NSManagedObjectModel mergedModelFromBundles:nil]copy];
        
        /*
         Adding support properties
         kAPIncrementalStoreUUIDAttributeName, kAPIncrementalStoreLastModifiedAttributeName and kAPIncrementalStoreObjectDeletedAttributeName
         for each entity present on model, then we don't need to mess up with the user coredata model
         */
        
        for (NSEntityDescription *entity in model.entities) {
            
            // Don't add properties for sub-entities, as they already exist in the super-entity
            if ([entity superentity]) {
                continue;
            }
            
            NSAttributeDescription *uuidProperty = [[NSAttributeDescription alloc] init];
            [uuidProperty setName:APObjectUIDAttributeName];
            [uuidProperty setAttributeType:NSStringAttributeType];
            [uuidProperty setIndexed:YES];
            
            NSAttributeDescription *lastModifiedProperty = [[NSAttributeDescription alloc] init];
            [lastModifiedProperty setName:APObjectLastModifiedAttributeName];
            [lastModifiedProperty setAttributeType:NSDateAttributeType];
            [lastModifiedProperty setIndexed:NO];
            
            NSAttributeDescription *deletedProperty = [[NSAttributeDescription alloc] init];
            [deletedProperty setName:APObjectIsDeletedAttributeName];
            [deletedProperty setAttributeType:NSBooleanAttributeType];
            [deletedProperty setIndexed:NO];
            [deletedProperty setOptional:NO];
            [deletedProperty setDefaultValue:@NO];
            
            NSAttributeDescription *isDirtyProperty = [[NSAttributeDescription alloc] init];
            [isDirtyProperty setName:APObjectIsDirtyAttributeName];
            [isDirtyProperty setAttributeType:NSBooleanAttributeType];
            [isDirtyProperty setIndexed:NO];
            [isDirtyProperty setOptional:NO];
            [isDirtyProperty setDefaultValue:@NO];
            
            [entity setProperties:[entity.properties arrayByAddingObjectsFromArray:@[uuidProperty,
                                                                                     lastModifiedProperty,
                                                                                     deletedProperty,
                                                                                     isDirtyProperty]]];
        }
        
         _testModel = model;
    }
    
    return _testModel;
}

- (NSManagedObjectContext*) testContext {
    
    if (!_testContext) {
        NSPersistentStoreCoordinator* psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.testModel];
        NSDictionary *options = @{ NSMigratePersistentStoresAutomaticallyOption: @YES,
                                   NSInferMappingModelAutomaticallyOption: @YES};
        
        NSURL *storeURL = [NSURL fileURLWithPath:[self pathToLocalStore]];
        
        NSError *error = nil;
        [psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:options error:&error];
        
        if (error) {
            NSLog(@"Error adding store to PSC:%@",error);
        }
        
        _testContext = [[NSManagedObjectContext alloc]initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        _testContext.persistentStoreCoordinator = psc;
    }
    return _testContext;
}

- (NSString *)documentsDirectory {
    
    NSString *documentsDirectory = nil;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    documentsDirectory = paths[0];
    return documentsDirectory;
}


- (NSString *)pathToLocalStore {
    
    return [[self documentsDirectory] stringByAppendingPathComponent:testSqliteFile];
}

- (void) removeCacheStore {
    
    if (AP_DEBUG_METHODS) { MLog() }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:[self pathToLocalStore]]) {
        NSError *deleteError = nil;
        BOOL delete = [fileManager removeItemAtURL:[NSURL fileURLWithPath:[self pathToLocalStore]] error:&deleteError];
        if (!delete) {
            [NSException raise:APIncrementalStoreExceptionLocalCacheStore format:@""];
        } else {
            if (AP_DEBUG_INFO) { DLog(@"Cache store removed succesfuly") };
        }
    }
}




@end
