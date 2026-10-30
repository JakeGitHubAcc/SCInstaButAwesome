#import <UIKit/UIKit.h>
#import "SCIAnalyzerStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface SCIAnalyzerListViewController : UITableViewController

- (instancetype)initWithStore:(SCIAnalyzerStore *)store list:(SCIAnalyzerList)list;

@end

NS_ASSUME_NONNULL_END
