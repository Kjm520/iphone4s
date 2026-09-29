#import "WaypointListViewController.h"

#import <CoreLocation/CoreLocation.h>

#import "Geo.h"

static UIColor *Green(void) {
    return [UIColor colorWithRed:0.25 green:1.0 blue:0.35 alpha:1];
}

@interface WaypointListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation WaypointListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 22, self.view.bounds.size.width, 40)];
    title.text = @"WAYPOINTS";
    title.font = [UIFont fontWithName:@"Menlo-Bold" size:17];
    title.textColor = Green();
    title.textAlignment = NSTextAlignmentCenter;
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:title];

    UIButton *clear = [UIButton buttonWithType:UIButtonTypeSystem];
    [clear setTitle:@"CLEAR" forState:UIControlStateNormal];
    clear.titleLabel.font = [UIFont fontWithName:@"Menlo" size:14];
    [clear setTitleColor:[UIColor grayColor] forState:UIControlStateNormal];
    clear.frame = CGRectMake(8, 22, 70, 40);
    [clear addTarget:self action:@selector(clearTapped)
    forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:clear];

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"DONE" forState:UIControlStateNormal];
    done.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:14];
    [done setTitleColor:Green() forState:UIControlStateNormal];
    done.frame = CGRectMake(self.view.bounds.size.width - 78, 22, 70, 40);
    done.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [done addTarget:self action:@selector(doneTapped)
   forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:done];

    self.table = [[UITableView alloc] initWithFrame:CGRectMake(0, 64,
        self.view.bounds.size.width, self.view.bounds.size.height - 64)
                                              style:UITableViewStylePlain];
    self.table.backgroundColor = [UIColor blackColor];
    self.table.separatorColor = [UIColor colorWithWhite:0.2 alpha:1];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.rowHeight = 56;
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth
                                | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.table];

    self.emptyLabel = [[UILabel alloc] initWithFrame:self.table.frame];
    self.emptyLabel.text = @"no pins yet\n\nMARK saves where you stand\nMap Bag adds them by map\nor typed coords";
    self.emptyLabel.font = [UIFont fontWithName:@"Menlo" size:14];
    self.emptyLabel.textColor = [UIColor grayColor];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.autoresizingMask = self.table.autoresizingMask;
    [self.view addSubview:self.emptyLabel];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.table reloadData];
}

- (void)clearTapped {
    if (self.onPick) self.onPick(nil);
    [self doneTapped];
}

- (void)doneTapped {
    if (self.onDone) self.onDone();
}

#pragma mark - table

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    NSInteger n = [WaypointStore shared].waypoints.count;
    self.emptyLabel.hidden = n > 0;
    return n;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"wp"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"wp"];
        cell.backgroundColor = [UIColor blackColor];
        cell.textLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:16];
        cell.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:12];
        cell.detailTextLabel.textColor = [UIColor grayColor];
        UIView *sel = [[UIView alloc] init];
        sel.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        cell.selectedBackgroundView = sel;
    }
    Waypoint *w = [WaypointStore shared].waypoints[indexPath.row];
    BOOL isTarget = [w.name isEqualToString:self.currentTargetName];
    cell.textLabel.text = isTarget
        ? [NSString stringWithFormat:@"→ %@", w.name] : w.name;
    cell.textLabel.textColor = isTarget ? Green()
        : [UIColor colorWithRed:0.7 green:0.9 blue:0.75 alpha:1];

    char m[16];
    geo_to_mgrs(w.lat, w.lon, m);
    if (self.fromFix) {
        CLLocation *dest = [[CLLocation alloc] initWithLatitude:w.lat longitude:w.lon];
        double dist = [self.fromFix distanceFromLocation:dest];
        double brg = geo_initial_bearing(self.fromFix.coordinate.latitude,
                                         self.fromFix.coordinate.longitude,
                                         w.lat, w.lon);
        NSString *d = dist < 1000
            ? [NSString stringWithFormat:@"%.0f m", dist]
            : [NSString stringWithFormat:@"%.2f km", dist / 1000.0];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  %03.0f°  %@",
                                     d, brg, [NSString stringWithUTF8String:m]];
    } else {
        cell.detailTextLabel.text = [NSString stringWithUTF8String:m];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView
        didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    Waypoint *w = [WaypointStore shared].waypoints[indexPath.row];
    if (self.onPick) self.onPick(w);
    [self doneTapped];
}


@end
