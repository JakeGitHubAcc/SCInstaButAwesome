#import "SCIProfileAnalyzerViewController.h"
#import "SCIAnalyzerAPI.h"
#import "SCIAnalyzerStore.h"
#import "SCIAnalyzerListViewController.h"
#import "SCIAnalyzerHistoryViewController.h"
#import "SCIAnalyzerMonitor.h"
#import "../../Utils.h"

typedef NS_ENUM(NSInteger, SCIAnalyzerSection) {
    SCIAnalyzerSectionAccount,
    SCIAnalyzerSectionResults,
    SCIAnalyzerSectionChanges,
    SCIAnalyzerSectionHistory,
    SCIAnalyzerSectionAlerts,
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

    // Background follower checks save into the same store
    [[NSNotificationCenter defaultCenter] addObserver:self.tableView selector:@selector(reloadData) name:SCIAnalyzerStoreDidChangeNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self.tableView name:SCIAnalyzerStoreDidChangeNotification object:nil];
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
        self.store = [SCIAnalyzerStore storeForUserPK:pk];
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
        case SCIAnalyzerSectionAlerts:  return [SCIUtils getBoolPref:@"analyzer_unfollow_alerts"] ? 3 : 1;
        case SCIAnalyzerSectionData:    return 2;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case SCIAnalyzerSectionResults: return @"Results";
        case SCIAnalyzerSectionChanges: return @"Since previous scan";
        case SCIAnalyzerSectionHistory: return @"History";
        case SCIAnalyzerSectionAlerts:  return @"Alerts";
        case SCIAnalyzerSectionData:    return @"Data";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == SCIAnalyzerSectionAccount) {
        return @"Scans load your full follower and following lists from Instagram, a page at a time. Large accounts take a few minutes. Scanning often, or acting on many accounts at once, can get your account temporarily limited.";
    }
    if (section == SCIAnalyzerSectionAlerts) {
        return @"Followers are re-checked when you open Instagram, at most once per interval, starting from your last scan. Run one manual scan first. Instagram doesn't say who blocked you, so a lost follower whose profile no longer loads is reported as a possible block; deactivated accounts look the same. Accounts with more than 20,000 followers are not checked automatically.";
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

        case SCIAnalyzerSectionAlerts: {
            content = [UIListContentConfiguration subtitleCellConfiguration];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            if (indexPath.row == 2) {
                content.text = @"Check every";
                content.image = [UIImage systemImageNamed:@"clock"];
                cell.accessoryView = [self intervalButton];
                break;
            }

            NSString *key = indexPath.row == 0 ? @"analyzer_unfollow_alerts" : @"analyzer_block_check";
            content.text = indexPath.row == 0 ? @"Unfollow alerts" : @"Check for blocks";
            content.secondaryText = indexPath.row == 0
                ? @"Get a notification when someone stops following you"
                : @"Also check whether people who unfollowed you can still be found";
            content.secondaryTextProperties.color = [UIColor secondaryLabelColor];
            content.image = [UIImage systemImageNamed:indexPath.row == 0 ? @"bell.badge" : @"hand.raised"];

            UISwitch *toggle = [UISwitch new];
            toggle.on = [SCIUtils getBoolPref:key];
            toggle.accessibilityIdentifier = key;
            [toggle addTarget:self action:@selector(alertSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
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

    if (store.scanInProgress) {
        [SCIUtils showErrorHUDWithDescription:@"A background check is running. Try again in a minute."];
        return;
    }
    store.scanInProgress = YES;

    self.scanning = YES;
    self.cancelRequested = NO;
    self.scanStatus = @"Loading followers…";

    __weak typeof(self) weakSelf = self;
    BOOL (^isCancelled)(void) = ^BOOL {
        return weakSelf == nil || weakSelf.cancelRequested;
    };

    void (^fail)(NSError *) = ^(NSError *error) {
        store.scanInProgress = NO;
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
            store.scanInProgress = NO;

            weakSelf.scanning = NO;
            [weakSelf.tableView reloadData];
        }];
    }];
}

- (UIButton *)intervalButton {
    double current = [SCIUtils getDoublePref:@"analyzer_check_hours"];
    if (current < 1) current = 6;

    NSMutableArray *actions = [NSMutableArray array];
    for (NSNumber *hours in @[@1, @3, @6, @12, @24]) {
        NSString *title = hours.integerValue == 1 ? @"1 hour" : [NSString stringWithFormat:@"%@ hours", hours];

        __weak typeof(self) weakSelf = self;
        UIAction *action = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(UIAction *a) {
            [[NSUserDefaults standardUserDefaults] setDouble:hours.doubleValue forKey:@"analyzer_check_hours"];
            [weakSelf.tableView reloadData];
        }];
        if (hours.doubleValue == current) action.state = UIMenuElementStateOn;
        [actions addObject:action];
    }

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:current == 1 ? @"1 hour" : [NSString stringWithFormat:@"%.0f hours", current] forState:UIControlStateNormal];
    button.menu = [UIMenu menuWithChildren:actions];
    button.showsMenuAsPrimaryAction = YES;
    [button sizeToFit];
    return button;
}

- (void)alertSwitchChanged:(UISwitch *)toggle {
    NSString *key = toggle.accessibilityIdentifier;
    [[NSUserDefaults standardUserDefaults] setBool:toggle.on forKey:key];

    if ([key isEqualToString:@"analyzer_unfollow_alerts"]) {
        if (toggle.on) [SCIAnalyzerMonitor requestNotificationPermission];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SCIAnalyzerSectionAlerts] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
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
