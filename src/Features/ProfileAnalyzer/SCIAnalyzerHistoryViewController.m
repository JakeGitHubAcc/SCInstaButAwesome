#import "SCIAnalyzerHistoryViewController.h"

@interface SCIAnalyzerHistoryViewController ()
@property (nonatomic, strong) SCIAnalyzerStore *store;
@property (nonatomic) SCIAnalyzerHistoryMode mode;

@property (nonatomic, copy, nullable) NSSet<NSString *> *typeFilter; // nil shows every event
@property (nonatomic, copy) NSArray<NSDictionary *> *rows;
@end

@implementation SCIAnalyzerHistoryViewController

- (instancetype)initWithStore:(SCIAnalyzerStore *)store mode:(SCIAnalyzerHistoryMode)mode {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];

    if (self) {
        self.store = store;
        self.mode = mode;
        self.title = mode == SCIAnalyzerHistoryModeChanges ? @"Change history" : @"Scan history";
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    if (self.mode == SCIAnalyzerHistoryModeChanges) [self updateFilterMenu];
    [self reloadRows];
}

// MARK: - Filtering

+ (NSArray<NSArray *> *)filters {
    return @[
        @[@"Everything", [NSNull null]],
        @[@"Followers gained or lost", @[@"new_follower", @"lost_follower"]],
        @[@"Following changes", @[@"new_following", @"lost_following", @"you_followed", @"you_unfollowed", @"you_removed"]],
        @[@"Username changes", @[@"username"]],
        @[@"Name changes", @[@"full_name"]],
        @[@"Profile picture changes", @[@"profile_pic"]],
    ];
}

- (void)updateFilterMenu {
    NSMutableArray *actions = [NSMutableArray array];

    for (NSArray *filter in [SCIAnalyzerHistoryViewController filters]) {
        NSSet *types = filter[1] == [NSNull null] ? nil : [NSSet setWithArray:filter[1]];

        __weak typeof(self) weakSelf = self;
        UIAction *action = [UIAction actionWithTitle:filter[0] image:nil identifier:nil handler:^(UIAction *a) {
            weakSelf.typeFilter = types;
            [weakSelf updateFilterMenu];
            [weakSelf reloadRows];
        }];

        BOOL selected = (types == nil && self.typeFilter == nil) || [types isEqualToSet:self.typeFilter];
        if (selected) action.state = UIMenuElementStateOn;

        [actions addObject:action];
    }

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"]
                                                                               menu:[UIMenu menuWithTitle:@"Show" children:actions]];
}

- (void)reloadRows {
    if (self.mode == SCIAnalyzerHistoryModeScans) {
        self.rows = self.store.scans;
    }
    else if (!self.typeFilter) {
        self.rows = self.store.events;
    }
    else {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *event in self.store.events) {
            if ([self.typeFilter containsObject:event[@"type"]]) [rows addObject:event];
        }
        self.rows = rows;
    }

    [self.tableView reloadData];
}

// MARK: - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.rows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.rows.count) return nil;

    return self.mode == SCIAnalyzerHistoryModeChanges
        ? @"Nothing yet. Changes show up here once you have scanned at least twice."
        : @"No scans yet.";
}

+ (NSString *)symbolForEventType:(NSString *)type {
    NSDictionary *symbols = @{
        @"new_follower":   @"person.badge.plus",
        @"lost_follower":  @"person.badge.minus",
        @"new_following":  @"plus.circle",
        @"lost_following": @"minus.circle",
        @"you_followed":   @"plus.circle.fill",
        @"you_unfollowed": @"minus.circle.fill",
        @"you_removed":    @"person.fill.xmark",
        @"username":       @"at",
        @"full_name":      @"textformat",
        @"profile_pic":    @"photo.circle",
    };
    return symbols[type] ?: @"circle";
}

+ (UIColor *)colorForEventType:(NSString *)type {
    if ([@[@"new_follower", @"new_following", @"you_followed"] containsObject:type]) return [UIColor systemGreenColor];
    if ([@[@"lost_follower", @"lost_following", @"you_unfollowed", @"you_removed"] containsObject:type]) return [UIColor systemRedColor];
    return [UIColor systemBlueColor];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    NSDictionary *row = self.rows[indexPath.row];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[row[@"date"] doubleValue]];
    NSString *dateString = [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];

    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.secondaryTextProperties.color = [UIColor secondaryLabelColor];

    if (self.mode == SCIAnalyzerHistoryModeChanges) {
        content.text = [SCIAnalyzerStore descriptionForEvent:row];
        content.secondaryText = dateString;
        content.image = [UIImage systemImageNamed:[SCIAnalyzerHistoryViewController symbolForEventType:row[@"type"]]];
        content.imageProperties.tintColor = [SCIAnalyzerHistoryViewController colorForEventType:row[@"type"]];
    }
    else {
        NSInteger followers = [row[@"followers"] integerValue];
        NSInteger following = [row[@"following"] integerValue];

        NSMutableString *text = [NSMutableString stringWithFormat:@"%ld followers · %ld following", (long)followers, (long)following];

        // Compare with the scan before this one
        if (indexPath.row + 1 < self.rows.count) {
            NSDictionary *older = self.rows[indexPath.row + 1];
            NSInteger followerDelta = followers - [older[@"followers"] integerValue];
            NSInteger followingDelta = following - [older[@"following"] integerValue];
            [text appendFormat:@"\n%+ld followers · %+ld following", (long)followerDelta, (long)followingDelta];
        }

        content.text = dateString;
        content.secondaryText = text;
        content.image = [UIImage systemImageNamed:@"chart.bar"];
    }

    cell.contentConfiguration = content;
    return cell;
}

@end
