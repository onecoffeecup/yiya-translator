#import <Foundation/Foundation.h>
#import <sqlite3.h>

// Called by the database session on its serial queue, before exposing the handle.
NSError *FYLearningMigrate(sqlite3 *db);
