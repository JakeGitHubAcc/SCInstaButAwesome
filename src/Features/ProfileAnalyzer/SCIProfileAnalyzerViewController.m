#import "SCIProfileAnalyzerViewController.h"
#import "SCIAnalyzerAPI.h"
#import "SCIAnalyzerStore.h"
#import "SCIAnalyzerListViewController.h"
#import "SCIAnalyzerHistoryViewController.h"
#import "../../Utils.h"

typedef NS_ENUM(NSInteger, SCIAnalyzerSection) {
    SCIAnalyzerSectionAccount,
    SCIAnalyzerSectionResults,
    SCIAnalyzerSectionChanges,
    SCIAnalyzerSectionHistory,
    SCIAnalyzerSectionData,
    SCIAnalyzerSectionCount,
};

@interface SCIProfileAnalyzerViewController ()
@property (nonatomic, strong, nullable) SCIAnalyzerStore *store;
@property (nonatomic, copy, nullable) NSString *username;

@property (nonatomic) BOOL scanning;
@property (nonatomic) BOOL cancelRequested;
@property (nonatomic, copy) NSString *scanStatus;
@end

@implementation SCIProfileAnalyzerViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Profile analyzer";
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self loadStore];
    [self.tableView reloadData];
}

- (void)loadStore {
    if (self.scanning) return;

    SCIAnalyzerAPI *api = [SCIAnalyzerAPI sharedInstance];
    NSString *pk = [api currentUserPK];
    self.username = [api currentUsername];

    if (!pk) {
        self.store = nil;
    }
    else if (![self.store.userPK isEqualToString:pk]) {
        self.store = [[SCIAnalyzerStore alloc] initWithUserPK:pk];
    }
}

// MARK: - Rows

- (NSArray<NSNumber *> *)listsForSection:(NSInteger)section {
    if (section == SCIAnalyzerSectionResults) {
        return @[@(SCIAnalyzerListMutuals), @(SCIAnalyzerListNotFollowingBack), @(SCIAnalyzerListFans)];
    }
    if (section == SCIAnalyzerSectionChanges) {
        return @[@(SCIAnalyzerListNewFollowers), @(SCIAnalyzerListLostFollowers), @(SCIAnalyzerListNewFollowing), @(SCIAnalyzerListUnfollowed)];
    }
    return @[];
}

+ (NSString *)symbolForList:(SCIAnalyzerList)list {
    switch (list) {
        case SCIAnalyzerListMutuals:          return @"arrow.left.arrow.right";
        case SCIAnalyzerListNotFollowingBack: return @"person.fill.xmark";
        case SCIAnalyzerListFans:             return @"person.fill.questionmark";
        case SCIAnalyzerListNewFollowers:     return @"person.badge.plus";
        case SCIAnalyzerListLostFollowers:    return @"person.badge.minus";
        case SCIAnalyzerListNewFollowing:     return @"plus.circle";
        case SCIAnalyzerListUnfollowed:       return @"minus.circle";
    }
    return @"person";
}

// MARK: - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.store ? SCIAnalyzerSectionCount : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case SCIAnalyzerSectionAccount: return self.store ? 2 : 1;
        case SCIAnalyzerSectionResults:
        case SCIAnalyzerSectionChanges: return [self listsForSection:section].count;
        case SCIAnalyzerSectionHistory: return 2;
        case SCIAnalyzerSectionData:    return 2;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case SCIAnalyzerSectionResults: return @"Results";
        case SCIAnalyzerSectionChanges: return @"Since previous scan";
        case SCIAnalyzerSectionHistory: return @"History";
        case SCIAnalyzerSectionData:    return @"Data";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == SCIAnalyzerSectionAccount) {
        return @"Scans load your full follower and following lists from Instagram, a page at a time. Large accounts take a few minutes. Scanning often, or acting on many accounts at once, can get your account temporarily limited.";
    }
    if (section == SCIAnalyzerSectionData) {
        return @"Scans are stored only on this device, separately for each account.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    UIListContentConfiguration *content = [UIListContentConfiguration valueCellConfiguration];

    switch (indexPath.section) {
        case SCIAnalyzerSectionAccount: {
            if (!self.store) {
                content = [UIListContentConfiguration subtitleCellConfiguration];
                content.text = @"Account not found";
                content.secondaryText = @"Close settings, browse Instagram for a few seconds, then come back.";
                content.image = [UIImage systemImageNamed:@"exclamationmark.triangle"];
                content.imageProperties.tintColor = [UIColor systemOrangeColor];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                break;
            }

            if (indexPath.row == 0) {
                content = [UIListContentConfiguration subtitleCellConfiguration];
                content.text = self.username.length ? [NSString stringWithFormat:@"@%@", self.username] : @"Your account";
                content.image = [UIImage systemImageNamed:@"person.crop.circle"];

                if (self.store.lastScanDate) {
                    NSString *date = [NSDateFormatter localizedStringFromDate:self.store.lastScanDate dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
                    content.secondaryText = [NSString stringWithFormat:@"%lu followers · %lu following\nLast scan %@",
                                             (unsigned long)self.store.followerCount, (unsigned long)self.store.followingCount, date];
                }
                else {
                    content.secondaryText = @"Not scanned yet";
                }
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            else {
                content = [UIListContentConfiguration cellConfiguration];
                if (self.scanning) {
                    content.text = self.scanStatus ?: @"Scanning…";
                    content.secondaryText = self.cancelRequested ? @"Cancelling…" : @"Tap to cancel";

                    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
                    [spinner startAnimating];
                    cell.accessoryView = spinner;
                }
                else {
                    content.text = self.store.lastScanDate ? @"Scan again" : @"Scan now";
                    content.textProperties.color = [SCIUtils SCIColor_Primary];
                    content.image = [UIImage systemImageNamed:@"arrow.clockwise"];
                    content.imageProperties.tintColor = [SCIUtils SCIColor_Primary];
                }
            }
            break;
        }

        case SCIAnalyzerSectionResults:
        case SCIAnalyzerSectionChanges: {
            SCIAnalyzerList list = [[self listsForSection:indexPath.section][indexPath.row] integerValue];

            content.text = [SCIAnalyzerStore titleForList:list];
            content.secondaryText = self.store.lastScanDate ? [NSString stringWithFormat:@"%lu", (unsigned long)[self.store usersForList:list].count] : @"–";
            content.image = [UIImage systemImageNamed:[SCIProfileAnalyzerViewController symbolForList:list]];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }

        case SCIAnalyzerSectionHistory: {
            if (indexPath.row == 0) {
                content.text = @"Change history";
                content.secondaryText = [NSString stringWithFormat:@"%lu", (unsigned long)self.store.events.count];
                content.image = [UIImage systemImageNamed:@"clock.arrow.circlepath"];
            }
            else {
                content.text = @"Scan history";
                content.secondaryText = [NSString stringWithFormat:@"%lu", (unsigned long)self.store.scans.count];
                content.image = [UIImage systemImageNamed:@"chart.line.uptrend.xyaxis"];
            }
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }

        case SCIAnalyzerSectionData: {
            content = [UIListContentConfiguration cellConfiguration];
            if (indexPath.row == 0) {
                content.text = @"Export as CSV";
                content.image = [UIImage systemImageNamed:@"square.and.arrow.up"];
            }
            else {
                content.text = @"Delete saved scans";
                content.textProperties.color = [UIColor systemRedColor];
                content.image = [UIImage systemImageNamed:@"trash"];
                content.imageProperties.tintColor = [UIColor systemRedColor];
            }
            break;
        }
    }

    cell.contentConfiguration = content;
    return cell;
}

// MARK: - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.store) return;

    switch (indexPath.section) {
        case SCIAnalyzerSectionAccount:
            if (indexPath.row == 1) {
                if (self.scanning) {
                    self.cancelRequested = YES;
                    [self.tableView reloadData];
                }
                else {
                    [self startScan];
                }
            }
            break;

        case SCIAnalyzerSectionResults:
        case SCIAnalyzerSectionChanges: {
            if (!self.store.lastScanDate) {
                [SCIUtils showErrorHUDWithDescription:@"Run a scan first"];
                return;
            }

            SCIAnalyzerList list = [[self listsForSection:indexPath.section][indexPath.row] integerValue];
            [self.navigationController pushViewController:[[SCIAnalyzerListViewController alloc] initWithStore:self.store list:list] animated:YES];
            break;
        }

        case SCIAnalyzerSectionHistory: {
            SCIAnalyzerHistoryMode mode = indexPath.row == 0 ? SCIAnalyzerHistoryModeChanges : SCIAnalyzerHistoryModeScans;
            [self.navigationController pushViewController:[[SCIAnalyzerHistoryViewController alloc] initWithStore:self.store mode:mode] animated:YES];
            break;
        }

        case SCIAnalyzerSectionData:
            if (indexPath.row == 0) {
                if (!self.store.lastScanDate) {
                    [SCIUtils showErrorHUDWithDescription:@"Run a scan first"];
                    return;
                }
                [SCIUtils showShareVC:[self.store exportCSV]];
            }
            else {
                [self confirmClearData];
            }
            break;
    }
}

// MARK: - Actions

- (void)setScanStatus:(NSString *)scanStatus {
    _scanStatus = [scanStatus copy];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:1 inSection:SCIAnalyzerSectionAccount]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)startScan {
    NSString *pk = self.store.userPK;
    SCIAnalyzerStore *store = self.store;
    SCIAnalyzerAPI *api = [SCIAnalyzerAPI sharedInstance];

    self.scanning = YES;
    self.cancelRequested = NO;
    self.scanStatus = @"Loading followers…";

    __weak typeof(self) weakSelf = self;
    BOOL (^isCancelled)(void) = ^BOOL {
        return weakSelf == nil || weakSelf.cancelRequested;
    };

    void (^fail)(NSError *) = ^(NSError *error) {
        weakSelf.scanning = NO;
        [weakSelf.tableView reloadData];

        if (error.code == -999) return;

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Scan failed" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [weakSelf presentViewController:alert animated:YES completion:nil];
    };

    [api fetchUserListOfKind:@"followers" userPK:pk progress:^(NSUInteger fetched) {
        weakSelf.scanStatus = [NSString stringWithFormat:@"Loading followers… %lu", (unsigned long)fetched];
    } isCancelled:isCancelled completion:^(NSArray<NSDictionary *> *followers, NSError *error) {
        if (error) { fail(error); return; }

        weakSelf.scanStatus = @"Loading following…";

        [api fetchUserListOfKind:@"following" userPK:pk progress:^(NSUInteger fetched) {
            weakSelf.scanStatus = [NSString stringWithFormat:@"Loading following… %lu", (unsigned long)fetched];
        } isCancelled:isCancelled completion:^(NSArray<NSDictionary *> *following, NSError *error) {
            if (error) { fail(error); return; }

            [store saveScanWithFollowers:followers following:following];

            weakSelf.scanning = NO;
            [weakSelf.tableView reloadData];
        }];
    }];
}

- (void)confirmClearData {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete saved scans?"
                                                                   message:@"This removes every scan, the change history and the scan history for this account."
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self.store clearAllData];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
