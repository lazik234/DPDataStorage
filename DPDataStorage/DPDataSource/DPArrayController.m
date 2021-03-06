//
//  DPArrayController.m
//  DP Commons
//
//  Created by Dmitriy Petrusevich on 23/07/15.
//  Copyright (c) 2015 Dmitriy Petrusevich. All rights reserved.
//

#import "DPArrayController.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - DPArrayControllerSection

@interface DPArrayControllerSection : NSObject  <NSFetchedResultsSectionInfo> {
    @public NSString *_name;
    @public NSString *_indexTitle;
}
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *indexTitle;
@property (nonatomic, readonly) NSUInteger numberOfObjects;
@property (nonatomic, strong) NSMutableArray *objects;

@property (nonatomic) BOOL isInserted;
@end

@implementation DPArrayControllerSection
@synthesize name = _name;
@synthesize indexTitle = _indexTitle;

- (instancetype)init {
    if ((self = [super init])) {
        _isInserted = YES;
    }
    return  self;
}

- (NSMutableArray *)objects {
    if (_objects == nil) _objects = [NSMutableArray new];
    return _objects;
}

- (NSString *)description {return [NSString stringWithFormat:@"%@ {numberOfObjects: %lu}", [super description], (unsigned long)self.numberOfObjects];}
- (NSUInteger)numberOfObjects {return self.objects.count;};
- (NSString *)name {return _name ?: @"";}

@end

#pragma mark - DPArrayController

NS_OPTIONS(NSUInteger, ResponseMask) {
    ResponseMaskDidChangeObject = 1 << 0,
    ResponseMaskDidChangeSection = 1 << 1,
    ResponseMaskWillChangeContent = 1 << 2,
    ResponseMaskDidChangeContent = 1 << 3,
};

static NSComparator inverseCompare = ^NSComparisonResult(NSIndexPath *obj1, NSIndexPath *obj2) {
    NSComparisonResult result = [obj1 compare:obj2];
    if (result == NSOrderedAscending) result = NSOrderedDescending;
    else if (result == NSOrderedDescending) result = NSOrderedAscending;
    return result;
};

@interface DPArrayController ()
@property (nonatomic, strong) NSMutableArray<DPArrayControllerSection *> *sections;
@property (nonatomic, assign) NSInteger updating;
@property (nonatomic, assign) enum ResponseMask responseMask;
@end

@implementation DPArrayController

- (instancetype)initWithDelegate:(id<DataSourceContainerControllerDelegate> _Nullable)delegate {
    if ((self = [self init])) {
        self.delegate = delegate;
    }
    return self;
}

- (instancetype)init {
    if ((self = [super init])) {
        self.removeEmptySectionsAutomaticaly = YES;
        self.sections = [NSMutableArray new];
    }
    return self;
}

- (void)setDelegate:(id<DataSourceContainerControllerDelegate> _Nullable)delegate {
    if (_delegate != delegate) {
        _delegate = delegate;

        enum ResponseMask responseMask = 0;
        if ([self.delegate respondsToSelector:@selector(controllerWillChangeContent:)]) {
            responseMask |= ResponseMaskWillChangeContent;
        }
        if ([self.delegate respondsToSelector:@selector(controllerDidChangeContent:)]) {
            responseMask |= ResponseMaskDidChangeContent;
        }
        if ([self.delegate respondsToSelector:@selector(controller:didChangeSection:atIndex:forChangeType:)]) {
            responseMask |= ResponseMaskDidChangeSection;
        }
        if ([self.delegate respondsToSelector:@selector(controller:didChangeObject:atIndexPath:forChangeType:newIndexPath:)]) {
            responseMask |= ResponseMaskDidChangeObject;
        }

        self.responseMask = responseMask;
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)managedObjectContextObjectsDidChange:(NSNotification *)notification {
    dispatch_block_t action = ^{
        NSDictionary *userInfo = notification.userInfo;

        NSArray *deletedPaths = [self pathsForObjects:userInfo[NSDeletedObjectsKey] sortComparator:inverseCompare];
        if (deletedPaths.count > 0) {
            [self startUpdating];
            for (NSIndexPath *indexPath in deletedPaths) {
                [self deleteObjectAtIndextPath:indexPath];
            }
            [self endUpdating];
        }

        NSArray *updatedPaths = [self pathsForObjects:userInfo[NSUpdatedObjectsKey] sortComparator:inverseCompare];
        if (updatedPaths.count > 0) {
            [self startUpdating];
            for (NSIndexPath *indexPath in updatedPaths) {
                [self reloadObjectAtIndextPath:indexPath];
            }
            [self endUpdating];
        }

        NSArray *refreshedPaths = [self pathsForObjects:userInfo[NSRefreshedObjectsKey] sortComparator:inverseCompare];
        if (refreshedPaths.count > 0) {
            [self startUpdating];
            for (NSIndexPath *indexPath in refreshedPaths) {
                [self reloadObjectAtIndextPath:indexPath];
            }
            [self endUpdating];
        }
    };

    [NSThread isMainThread] ? action() : dispatch_async(dispatch_get_main_queue(), action);
}


#pragma mark - Helper

- (NSArray *)pathsForObjects:(id<NSFastEnumeration>)collection sortComparator:(NSComparator)comparator {
    NSMutableArray *paths = [NSMutableArray new];
    for (id object in collection) {
        NSIndexPath *path = [self indexPathForObject:object];
        path ? [paths addObject:path] : nil;
    }
    comparator ? [paths sortUsingComparator:comparator] : nil;

    return paths;
}

- (BOOL)isObjectMatchFilter:(id)object {
    BOOL result = YES;
    if (self.filter) {
        if ([object isKindOfClass:[NSManagedObject class]]) {
            NSManagedObject *managedObject = object;

            NSManagedObjectContext *context = [managedObject managedObjectContext];
            NSFetchRequest *request = [[NSFetchRequest alloc] init];
            request.entity = managedObject.entity;

            NSPredicate *selfPredicate = [NSPredicate predicateWithFormat:@"self == %@", [managedObject objectID]];
            request.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[selfPredicate, self.filter]];
            request.fetchLimit = 1;

            result = ([context countForFetchRequest:request error:nil] > 0);
        }
        else {
            result = [self.filter evaluateWithObject:object];
        }
    }
    return result;
}

- (void)setFilter:(NSPredicate * _Nullable)filter {
    if (_filter != filter) {
        _filter = filter;

        if (filter != nil) {
            [self startUpdating];
            for (NSUInteger section = 0; section < self.sections.count; section++) {
                DPArrayControllerSection *sectionInfo = self.sections[section];
                for (NSInteger i = sectionInfo.objects.count; i > 0; i--) {
                    NSInteger row = i - 1;
                    [self reloadObjectAtIndextPath:[NSIndexPath indexPathForItem:row inSection:section]];
                }
            }
            [self endUpdating];
        }
    }
}

#pragma mark - Editing: Items

- (void)removeAllObjects {
    if (self.sections.count) {
        [self startUpdating];

        for (NSUInteger section = self.sections.count; section > 0; section--) {
            [self removeSectionAtIndex:(section - 1)];
        }

        [self endUpdating];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextObjectsDidChangeNotification object:nil];
    }
}

- (void)insertObject:(id)object atIndextPath:(NSIndexPath *)indexPath {
    NSParameterAssert(indexPath != nil);

    if (object != nil && [self isObjectMatchFilter:object]) {
        [self startUpdating];
        [self insertSectionAtIndex:indexPath.section];

        DPArrayControllerSection *sectionInfo = self.sections[indexPath.section];
        [sectionInfo.objects insertObject:object atIndex:indexPath.row];

        if ([object isKindOfClass:[NSManagedObject class]]) {
            NSManagedObjectContext *context = [object managedObjectContext];
            [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextObjectsDidChangeNotification object:context];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextObjectsDidChange:) name:NSManagedObjectContextObjectsDidChangeNotification object:context];
        }

        if (self.responseMask & ResponseMaskDidChangeObject) {
            [self.delegate controller:self didChangeObject:object atIndexPath:nil forChangeType:NSFetchedResultsChangeInsert newIndexPath:indexPath];
        }

        [self endUpdating];
    }
}

- (void)deleteObjectAtIndextPath:(NSIndexPath *)indexPath {
    NSParameterAssert(indexPath != nil);

    [self startUpdating];

    DPArrayControllerSection *sectionInfo = self.sections[indexPath.section];
    id object = sectionInfo.objects[indexPath.row];
    [sectionInfo.objects removeObjectAtIndex:indexPath.row];

    if (self.responseMask & ResponseMaskDidChangeObject) {
        [self.delegate controller:self didChangeObject:object atIndexPath:indexPath forChangeType:NSFetchedResultsChangeDelete newIndexPath:nil];
    }

    [self endUpdating];
}

- (void)reloadObjectAtIndextPath:(NSIndexPath *)indexPath {
    NSParameterAssert(indexPath != nil);

    DPArrayControllerSection *sectionInfo = self.sections[indexPath.section];
    id object = sectionInfo.objects[indexPath.row];

    if ([self isObjectMatchFilter:object] == YES) {
        if (self.responseMask & ResponseMaskDidChangeObject) {
            [self startUpdating];
            [self.delegate controller:self didChangeObject:object atIndexPath:indexPath forChangeType:NSFetchedResultsChangeUpdate newIndexPath:nil];
            [self endUpdating];
        }
    }
    else if (self.filter != nil) {
        [self deleteObjectAtIndextPath:indexPath];
    }
}

- (void)moveObjectAtIndextPath:(NSIndexPath *)indexPath toIndexPath:(NSIndexPath *)newIndexPath {
    NSParameterAssert(indexPath != nil);
    NSParameterAssert(newIndexPath != nil);

    if ([indexPath isEqual:newIndexPath]) {
        return;
    }

    [self startUpdating];
    [self insertSectionAtIndex:newIndexPath.section];

    id object = [self objectAtIndexPath:indexPath];

    DPArrayControllerSection *sectionInfo = self.sections[indexPath.section];
    [sectionInfo.objects removeObjectAtIndex:indexPath.row];

    sectionInfo = self.sections[newIndexPath.section];
    [sectionInfo.objects insertObject:object atIndex:newIndexPath.row];

    if (self.responseMask & ResponseMaskDidChangeObject) {
        [self.delegate controller:self didChangeObject:object atIndexPath:indexPath forChangeType:NSFetchedResultsChangeMove newIndexPath:newIndexPath];
    }

    [self endUpdating];
}

#pragma mark - Editing: Sections

- (void)insertSectionAtIndex:(NSUInteger)index {
    [self startUpdating];

    while (index >= self.sections.count) {
        DPArrayControllerSection *section = [DPArrayControllerSection new];
        [self.sections addObject:section];

        if (self.responseMask & ResponseMaskDidChangeSection) {
            [self.delegate controller:self didChangeSection:section atIndex:(self.sections.count - 1) forChangeType:NSFetchedResultsChangeInsert];
        }
    }

    [self endUpdating];
}

- (void)removeSectionAtIndex:(NSUInteger)index {
    [self startUpdating];

    DPArrayControllerSection *section = self.sections[index];
    [self.sections removeObjectAtIndex:index];

    if (self.responseMask & ResponseMaskDidChangeSection) {
        [self.delegate controller:self didChangeSection:section atIndex:index forChangeType:NSFetchedResultsChangeDelete];
    }

    [self endUpdating];
}

- (void)reloadSectionAtIndex:(NSUInteger)index {
    [self startUpdating];

    DPArrayControllerSection *section = self.sections[index];
    if (self.responseMask & ResponseMaskDidChangeSection) {
        [self.delegate controller:self didChangeSection:section atIndex:index forChangeType:NSFetchedResultsChangeUpdate];
    }

    [self endUpdating];
}

- (void)removeEmptySections {
    NSInteger count = self.sections.count;

    if (count > 0) {
        BOOL hasEmptySections = NO;

        for (NSInteger i = count; i > 0; i--) {
            NSInteger index = i - 1;
            DPArrayControllerSection *section = self.sections[index];
            if ([section numberOfObjects] == 0 && section.isInserted == NO) {
                hasEmptySections ? nil : [self startUpdating];
                [self removeSectionAtIndex:index];
                hasEmptySections = YES;
            }
        }
        
        hasEmptySections ? [self endUpdating] : nil;
    }
}

- (void)setSectionName:(NSString *)name atIndex:(NSUInteger)index {
    if (index <= self.sections.count) {
        [self startUpdating];
        [self insertSectionAtIndex:index];

        DPArrayControllerSection *section = self.sections[index];
        section->_name = name;
        
        [self endUpdating];
    }
    else {
        DPArrayControllerSection *section = self.sections[index];
        section->_name = name;
    }
}

#pragma mark - Editing: Complex

- (void)removeAllObjectsAtSection:(NSInteger)section {
    if (section < self.sections.count) {
        [self startUpdating];

        DPArrayControllerSection *sectionInfo = self.sections[section];
        for (NSInteger i = sectionInfo.objects.count; i > 0; i--) {
            NSInteger row = i - 1;
            [self deleteObjectAtIndextPath:[NSIndexPath indexPathForItem:row inSection:section]];
        }

        [self endUpdating];
    }
}

- (void)addObjects:(NSArray *)objects atSection:(NSInteger)section {
    NSParameterAssert(section >= 0);

    if (objects.count > 0) {
        [self startUpdating];
        [self insertSectionAtIndex:section];

        if (self.responseMask & ResponseMaskDidChangeObject) {
            for (id object in objects) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForItem:[self.sections[section] numberOfObjects] inSection:section];
                [self insertObject:object atIndextPath:indexPath];
            }
        }
        else {
            if (self.filter) {
                NSMutableArray *filtedArray = [[NSMutableArray alloc] initWithCapacity:objects.count];
                for (id object in objects) {
                    if ([self isObjectMatchFilter:object]) {
                        [filtedArray addObject:object];
                    }
                }

                DPArrayControllerSection *sectionInfo = self.sections[section];
                [sectionInfo.objects addObjectsFromArray:filtedArray];

                for (id object in filtedArray) {
                    if ([object isKindOfClass:[NSManagedObject class]]) {
                        NSManagedObjectContext *context = [object managedObjectContext];
                        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextObjectsDidChangeNotification object:context];
                        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextObjectsDidChange:) name:NSManagedObjectContextObjectsDidChangeNotification object:context];
                    }
                }

            }
            else {
                DPArrayControllerSection *sectionInfo = self.sections[section];
                [sectionInfo.objects addObjectsFromArray:objects];

                for (id object in objects) {
                    if ([object isKindOfClass:[NSManagedObject class]]) {
                        NSManagedObjectContext *context = [object managedObjectContext];
                        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextObjectsDidChangeNotification object:context];
                        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextObjectsDidChange:) name:NSManagedObjectContextObjectsDidChangeNotification object:context];
                    }
                }
            }
        }

        [self endUpdating];
    }
}

- (void)setObjects:(NSArray *)newObjects atSection:(NSInteger)section {
    if (section < self.sections.count) {
        [self startUpdating];

        if (newObjects.count == 0) {
            [self removeAllObjectsAtSection:section];
        }
        else {
            [self removeAllObjectsAtSection:section];
            [self addObjects:newObjects atSection:section];
        }

        [self endUpdating];
    }
    else {
        [self addObjects:newObjects atSection:section];
    }
}

#pragma mark - Updating

- (void)startUpdating {
    if (self.updating == 0) {
        if (self.responseMask & ResponseMaskWillChangeContent) {
            [self.delegate controllerWillChangeContent:self];
        }
    }
    self.updating++;
}

- (void)endUpdating {
    self.updating--;
    if (self.updating == 0) {
        // Remove exist empty sections
        if (self.removeEmptySectionsAutomaticaly) {
            [self removeEmptySections];
        }

        if (self.responseMask & ResponseMaskDidChangeContent) {
            [self.delegate controllerDidChangeContent:self];
        }

        for (DPArrayControllerSection *section in self.sections) {
            section.isInserted = NO;
        }

        // Remove inserted empty sections
        if (self.removeEmptySectionsAutomaticaly) {
            [self removeEmptySections];
        }
    }
}

#pragma mark - Getters

- (NSInteger)numberOfSections {
    return [self.sections count];
}

- (NSInteger)numberOfItemsInSection:(NSInteger)section {
    NSInteger result = 0;
    if (section < [self.sections count] && section >= 0) {
        id <NSFetchedResultsSectionInfo> sectionInfo =  [self.sections objectAtIndex:section];
        result = [sectionInfo numberOfObjects];
    }
    return result;
}

- (BOOL)hasData {
    for (id <NSFetchedResultsSectionInfo> section in self.sections) {
        if ([section numberOfObjects] > 0) return YES;
    }
    return NO;
}

- (id)objectAtIndexPath:(NSIndexPath *)indexPath {
    id result = nil;
    if (indexPath) {
        DPArrayControllerSection *sectionInfo = self.sections[indexPath.section];
        result = sectionInfo.objects[indexPath.row];
    }
    return result;
}

- (NSIndexPath *)indexPathForObject:(id)object {
    NSIndexPath *result = nil;

    if (object) {
        id left = [object isKindOfClass:[NSManagedObject class]] ? [object objectID] : object;

        for (NSInteger section = 0; section < self.sections.count; section++) {
            DPArrayControllerSection *sectionInfo = self.sections[section];
            
            for (NSInteger index = 0; index < sectionInfo.objects.count; index++) {
                id right = sectionInfo.objects[index];
                right = [right isKindOfClass:[NSManagedObject class]] ? [right objectID] : right;

                if ([left isEqual:right]) {
                    result = [NSIndexPath indexPathForItem:index inSection:section];
                    break;
                }
            }
        }
    }

    return result;
}

- (NSArray *)fetchedObjects {
    NSMutableArray *fetchedObjects = [NSMutableArray array];
    for (id <NSFetchedResultsSectionInfo> section in self.sections) {
        [fetchedObjects addObjectsFromArray:section.objects];
    }
    return fetchedObjects;
}

@end

NS_ASSUME_NONNULL_END
