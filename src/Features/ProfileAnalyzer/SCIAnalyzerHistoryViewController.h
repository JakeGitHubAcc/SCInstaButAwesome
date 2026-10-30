#import <UIKit/UIKit.h>
#import "SCIAnalyzerStore.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIAnalyzerHistoryMode) {
    SCIAnalyzerHistoryModeChanges,
    SCIAnalyzerHistoryModeScans,
};

@interface SCIAnalyzerHistoryViewController : UITableViewController

- (instancetype)initWithStore:(SCIAnalyzerStore *)store mode:(SCIAnalyzerHistoryMode)mode;

@end

NS_ASSUME_NONNULL_END
