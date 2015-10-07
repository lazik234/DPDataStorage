//
//  DPBaseDataSource.h
//  DP Commons
//
//  Created by Dmitriy Petrusevich on 27/04/15.
//  Copyright (c) 2015 Dmitriy Petrusevich. All rights reserved.
//

@import UIKit;

#import "DPDataSourceCell.h"
#import "DPDataSourceContainer.h"

@interface NSFetchedResultsController (DataSourceContainerController) <DataSourceContainerController>
@end

IB_DESIGNABLE
@interface DPBaseDataSource : NSObject <DataSourceContainerControllerDelegate, NSFetchedResultsControllerDelegate>
@property (nonatomic, weak) IBOutlet id forwardDelegate;
@property (nonatomic, strong) id<DataSourceContainerController> listController;

- (NSInteger)numberOfSections;
- (NSInteger)numberOfItemsInSection:(NSInteger)section;

- (id)objectAtIndexPath:(NSIndexPath *)indexPath;
- (NSIndexPath *)indexPathForObject:(id)object;
@end



