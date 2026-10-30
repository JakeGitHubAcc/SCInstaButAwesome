#import "SCIAnalyzerListViewController.h"
#import "SCIAnalyzerAPI.h"
#import "../../Utils.h"

static CGFloat const kAvatarSize = 40.0;

@interface SCIAnalyzerListViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) SCIAnalyzerStore *store;
@property (nonatomic) SCIAnalyzerList list;

@property (nonatomic, copy) NSArray<NSDictionary *> *users;
@property (nonatomic, copy) NSArray<NSDictionary *> *filteredUsers;
@property (nonatomic) BOOL sortAlphabetically;

@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic) BOOL bulkCancelled;
@end

@implementation SCIAnalyzerListViewController

+ (NSCache<NSString *, UIImage *> *)avatarCache {
    static NSCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 1000;
    });
    return cache;
}

- (instancetype)initWithStore:(SCIAnalyzerStore *)store list:(SCIAnalyzerList)list {
    self = [super initWithStyle:UITableViewStylePlain];

    if (self) {
        self.store = store;
        self.list = list;
        self.title = [SCIAnalyzerStore titleForList:list];
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.allowsMultipleSelectionDuringEditing = YES;
    self.tableView.rowHeight = 60;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search username or name";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    [self updateNavigationItems];
    [self reloadUsers];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self.navigationController setToolbarHidden:YES animated:animated];
}

// MARK: - Data

- (void)reloadUsers {
    NSArray *users = [self.store usersForList:self.list];

    if (self.sortAlphabetically) {
        users = [users sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"username"] localizedCaseInsensitiveCompare:b[@"username"]];
        }];
    }

    self.users = users;
    [self applySearch];
}

- (void)applySearch {
    NSString *query = self.searchController.searchBar.text;

    if (!query.length) {
        self.filteredUsers = self.users;
    }
    else {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"username CONTAINS[cd] %@ OR full_name CONTAINS[cd] %@", query, query];
        self.filteredUsers = [self.users filteredArrayUsingPredicate:predicate];
    }

    [self.tableView reloadData];
    [self updateToolbar];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self applySearch];
}

// MARK: - Navigation & toolbar

- (void)updateNavigationItems {
    if (self.tableView.isEditing) {
        self.navigationItem.rightBarButtonItems = @[
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(toggleEditing)]
        ];
        return;
    }

    __weak typeof(self) weakSelf = self;
    UIAction *defaultOrder = [UIAction actionWithTitle:@"Instagram order" image:nil identifier:nil handler:^(UIAction *action) {
        weakSelf.sortAlphabetically = NO;
        [weakSelf updateNavigationItems];
        [weakSelf reloadUsers];
    }];
    UIAction *alphabetical = [UIAction actionWithTitle:@"Username A–Z" image:nil identifier:nil handler:^(UIAction *action) {
        weakSelf.sortAlphabetically = YES;
        [weakSelf updateNavigationItems];
        [weakSelf reloadUsers];
    }];
    (self.sortAlphabetically ? alphabetical : defaultOrder).state = UIMenuElementStateOn;

    UIMenu *sortMenu = [UIMenu menuWithTitle:@"Sort" children:@[defaultOrder, alphabetical]];

    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Select" style:UIBarButtonItemStylePlain target:self action:@selector(toggleEditing)],
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.arrow.down"] menu:sortMenu]
    ];
}

- (void)toggleEditing {
    [self.tableView setEditing:!self.tableView.isEditing animated:YES];
    [self.navigationController setToolbarHidden:!self.tableView.isEditing animated:YES];

    [self updateNavigationItems];
    [self updateToolbar];
}

- (NSArray<NSDictionary *> *)selectedUsers {
    NSMutableArray *users = [NSMutableArray array];
    for (NSIndexPath *indexPath in self.tableView.indexPathsForSelectedRows) {
        if (indexPath.row < self.filteredUsers.count) [users addObject:self.filteredUsers[indexPath.row]];
    }
    return users;
}

- (void)updateToolbar {
    if (!self.tableView.isEditing) return;

    NSArray *selected = [self selectedUsers];
    BOOL allSelected = selected.count > 0 && selected.count == self.filteredUsers.count;

    UIBarButtonItem *selectAll = [[UIBarButtonItem alloc] initWithTitle:allSelected ? @"Deselect all" : @"Select all"
                                                                  style:UIBarButtonItemStylePlain
                                                                 target:self
                                                                 action:@selector(toggleSelectAll)];

    __weak typeof(self) weakSelf = self;
    NSMutableArray *actions = [NSMutableArray array];

    NSUInteger followingCount = 0, notFollowingCount = 0, followerCount = 0;
    for (NSDictionary *user in selected) {
        if ([self.store isFollowing:user[@"pk"]]) followingCount++; else notFollowingCount++;
        if ([self.store isFollower:user[@"pk"]]) followerCount++;
    }

    if (followingCount) {
        UIAction *action = [UIAction actionWithTitle:[NSString stringWithFormat:@"Unfollow %lu", (unsigned long)followingCount]
                                               image:[UIImage systemImageNamed:@"person.badge.minus"]
                                          identifier:nil
                                             handler:^(UIAction *a) { [weakSelf runBulkAction:SCIAnalyzerFriendshipActionUnfollow]; }];
        action.attributes = UIMenuElementAttributesDestructive;
        [actions addObject:action];
    }
    if (followerCount) {
        UIAction *action = [UIAction actionWithTitle:[NSString stringWithFormat:@"Remove %lu follower%@", (unsigned long)followerCount, followerCount == 1 ? @"" : @"s"]
                                               image:[UIImage systemImageNamed:@"person.fill.xmark"]
                                          identifier:nil
                                             handler:^(UIAction *a) { [weakSelf runBulkAction:SCIAnalyzerFriendshipActionRemoveFollower]; }];
        action.attributes = UIMenuElementAttributesDestructive;
        [actions addObject:action];
    }
    if (notFollowingCount) {
        [actions addObject:[UIAction actionWithTitle:[NSString stringWithFormat:@"Follow %lu", (unsigned long)notFollowingCount]
                                               image:[UIImage systemImageNamed:@"person.badge.plus"]
                                          identifier:nil
                                             handler:^(UIAction *a) { [weakSelf runBulkAction:SCIAnalyzerFriendshipActionFollow]; }]];
    }

    UIBarButtonItem *actionsItem = [[UIBarButtonItem alloc] initWithTitle:[NSString stringWithFormat:@"Actions (%lu)", (unsigned long)selected.count]
                                                                     menu:[UIMenu menuWithChildren:actions]];
    actionsItem.enabled = actions.count > 0;

    self.toolbarItems = @[
        selectAll,
        [UIBarButtonItem flexibleSpaceItem],
        actionsItem
    ];
}

- (void)toggleSelectAll {
    BOOL allSelected = [self selectedUsers].count == self.filteredUsers.count;

    for (NSInteger row = 0; row < self.filteredUsers.count; row++) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        if (allSelected) [self.tableView deselectRowAtIndexPath:indexPath animated:NO];
        else [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
    }

    [self updateToolbar];
}

// MARK: - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredUsers.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (!self.filteredUsers.count) return self.searchController.searchBar.text.length ? @"No matches" : @"Nobody here";
    return [NSString stringWithFormat:@"%lu account%@", (unsigned long)self.filteredUsers.count, self.filteredUsers.count == 1 ? @"" : @"s"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"user"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"user"];
    NSDictionary *user = self.filteredUsers[indexPath.row];

    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];

    NSMutableString *username = [NSMutableString stringWithString:user[@"username"] ?: @""];
    if ([user[@"is_verified"] boolValue]) [username appendString:@" ✓"];
    if ([user[@"is_private"] boolValue]) [username appendString:@" 🔒"];
    content.text = username;
    content.secondaryText = [user[@"full_name"] length] ? user[@"full_name"] : nil;
    content.secondaryTextProperties.color = [UIColor secondaryLabelColor];

    UIImage *avatar = [[SCIAnalyzerListViewController avatarCache] objectForKey:user[@"pk"]];
    content.image = avatar ?: [UIImage systemImageNamed:@"person.crop.circle.fill"];
    content.imageProperties.tintColor = [UIColor systemGray3Color];
    content.imageProperties.reservedLayoutSize = CGSizeMake(kAvatarSize, kAvatarSize);
    content.imageProperties.maximumSize = CGSizeMake(kAvatarSize, kAvatarSize);
    content.imageProperties.cornerRadius = kAvatarSize / 2.0;

    if (!avatar) [self loadAvatarForUser:user];

    cell.contentConfiguration = content;
    return cell;
}

- (void)loadAvatarForUser:(NSDictionary *)user {
    NSString *pk = user[@"pk"];
    NSURL *url = [NSURL URLWithString:user[@"profile_pic_url"] ?: @""];
    if (!pk || !url.host) return;

    static NSMutableSet *loading;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ loading = [NSMutableSet set]; });

    if ([loading containsObject:pk]) return;
    [loading addObject:pk];

    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        UIImage *image = data ? [UIImage imageWithData:data] : nil;

        UIImage *rounded = nil;
        if (image) {
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(kAvatarSize, kAvatarSize)];
            rounded = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, kAvatarSize, kAvatarSize)] addClip];
                [image drawInRect:CGRectMake(0, 0, kAvatarSize, kAvatarSize)];
            }];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [loading removeObject:pk];
            if (!rounded) return;

            [[SCIAnalyzerListViewController avatarCache] setObject:rounded forKey:pk];

            SCIAnalyzerListViewController *strongSelf = weakSelf;
            if (!strongSelf) return;

            NSMutableArray *visible = [NSMutableArray array];
            for (NSIndexPath *indexPath in strongSelf.tableView.indexPathsForVisibleRows) {
                if (indexPath.row < strongSelf.filteredUsers.count && [strongSelf.filteredUsers[indexPath.row][@"pk"] isEqualToString:pk]) {
                    [visible addObject:indexPath];
                }
            }
            if (visible.count) [strongSelf.tableView reconfigureRowsAtIndexPaths:visible];
        });
    }] resume];
}

// MARK: - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView.isEditing) {
        [self updateToolbar];
        return;
    }

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self showActionsForUser:self.filteredUsers[indexPath.row] sourceView:[tableView cellForRowAtIndexPath:indexPath]];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView.isEditing) [self updateToolbar];
}

- (void)showActionsForUser:(NSDictionary *)user sourceView:(UIView *)sourceView {
    NSString *username = user[@"username"];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"@%@", username]
                                                                   message:[user[@"full_name"] length] ? user[@"full_name"] : nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Open profile" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self openProfile:username];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy username" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UIPasteboard generalPasteboard].string = username;
    }]];

    if ([self.store isFollowing:user[@"pk"]]) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Unfollow" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self performAction:SCIAnalyzerFriendshipActionUnfollow onUser:user];
        }]];
    }
    else {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Follow" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self performAction:SCIAnalyzerFriendshipActionFollow onUser:user];
        }]];
    }

    if ([self.store isFollower:user[@"pk"]]) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Remove follower" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self performAction:SCIAnalyzerFriendshipActionRemoveFollower onUser:user];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    sheet.popoverPresentationController.sourceView = sourceView ?: self.view;
    sheet.popoverPresentationController.sourceRect = (sourceView ?: self.view).bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)openProfile:(NSString *)username {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"instagram://user?username=%@", username]];
    if (!url) return;

    void (^open)(void) = ^{
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    };

    // Close the settings sheet so the profile opens on top of Instagram
    UIViewController *presenter = self.navigationController.presentingViewController;
    if (presenter) [presenter dismissViewControllerAnimated:YES completion:open];
    else open();
}

// MARK: - Friendship actions

- (void)recordAction:(SCIAnalyzerFriendshipAction)action onUser:(NSDictionary *)user {
    switch (action) {
        case SCIAnalyzerFriendshipActionFollow:         [self.store recordFollow:user]; break;
        case SCIAnalyzerFriendshipActionUnfollow:       [self.store recordUnfollow:user]; break;
        case SCIAnalyzerFriendshipActionRemoveFollower: [self.store recordRemovedFollower:user]; break;
    }
}

- (BOOL)action:(SCIAnalyzerFriendshipAction)action appliesToUser:(NSDictionary *)user {
    switch (action) {
        case SCIAnalyzerFriendshipActionFollow:         return ![self.store isFollowing:user[@"pk"]];
        case SCIAnalyzerFriendshipActionUnfollow:       return [self.store isFollowing:user[@"pk"]];
        case SCIAnalyzerFriendshipActionRemoveFollower: return [self.store isFollower:user[@"pk"]];
    }
    return NO;
}

+ (NSString *)verbForAction:(SCIAnalyzerFriendshipAction)action {
    switch (action) {
        case SCIAnalyzerFriendshipActionFollow:         return @"Following";
        case SCIAnalyzerFriendshipActionUnfollow:       return @"Unfollowing";
        case SCIAnalyzerFriendshipActionRemoveFollower: return @"Removing";
    }
    return @"";
}

- (void)performAction:(SCIAnalyzerFriendshipAction)action onUser:(NSDictionary *)user {
    JGProgressHUD *hud = [[JGProgressHUD alloc] init];
    hud.textLabel.text = [SCIAnalyzerListViewController verbForAction:action];
    [hud showInView:self.navigationController.view ?: self.view];

    [[SCIAnalyzerAPI sharedInstance] performAction:action userPK:user[@"pk"] completion:^(NSError *error) {
        [hud dismiss];

        if (error) {
            [SCIUtils showErrorHUDWithDescription:error.localizedDescription dismissAfterDelay:3.0];
            return;
        }

        [self recordAction:action onUser:user];
        [self reloadUsers];
    }];
}

- (void)runBulkAction:(SCIAnalyzerFriendshipAction)action {
    NSMutableArray *users = [NSMutableArray array];
    for (NSDictionary *user in [self selectedUsers]) {
        if ([self action:action appliesToUser:user]) [users addObject:user];
    }
    if (!users.count) return;

    NSString *verb = [SCIAnalyzerListViewController verbForAction:action];
    NSString *message = [NSString stringWithFormat:@"%@ %lu account%@, a few seconds apart.%@",
                         verb, (unsigned long)users.count, users.count == 1 ? @"" : @"s",
                         users.count > 25 ? @"\n\nActing on a lot of accounts at once can get your account temporarily limited." : @""];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Are you sure?" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self startBulkAction:action users:users];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)startBulkAction:(SCIAnalyzerFriendshipAction)action users:(NSArray<NSDictionary *> *)users {
    self.bulkCancelled = NO;

    JGProgressHUD *hud = [[JGProgressHUD alloc] init];
    hud.detailTextLabel.text = @"Tap to stop";

    __weak typeof(self) weakSelf = self;
    hud.tapOnHUDViewBlock = ^(JGProgressHUD *HUD) {
        weakSelf.bulkCancelled = YES;
        HUD.detailTextLabel.text = @"Stopping…";
    };

    [hud showInView:self.navigationController.view ?: self.view];
    [self performBulkAction:action users:users index:0 hud:hud];
}

- (void)performBulkAction:(SCIAnalyzerFriendshipAction)action users:(NSArray<NSDictionary *> *)users index:(NSUInteger)index hud:(JGProgressHUD *)hud {
    if (index >= users.count || self.bulkCancelled) {
        [hud dismiss];
        [SCIUtils showToastForDuration:2.0 title:[NSString stringWithFormat:@"Done: %lu of %lu", (unsigned long)index, (unsigned long)users.count]];

        if (self.tableView.isEditing) [self toggleEditing];
        [self reloadUsers];
        return;
    }

    NSDictionary *user = users[index];
    hud.textLabel.text = [NSString stringWithFormat:@"%@ %lu of %lu\n@%@", [SCIAnalyzerListViewController verbForAction:action], (unsigned long)index + 1, (unsigned long)users.count, user[@"username"]];

    [[SCIAnalyzerAPI sharedInstance] performAction:action userPK:user[@"pk"] completion:^(NSError *error) {
        if (error) {
            [hud dismiss];
            [SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:@"Stopped after %lu: %@", (unsigned long)index, error.localizedDescription] dismissAfterDelay:4.0];

            if (self.tableView.isEditing) [self toggleEditing];
            [self reloadUsers];
            return;
        }

        [self recordAction:action onUser:user];

        double delay = 2.0 + (arc4random_uniform(2000) / 1000.0);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self performBulkAction:action users:users index:index + 1 hud:hud];
        });
    }];
}

@end
