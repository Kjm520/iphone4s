#import "MBTilesOverlay.h"

#import <UIKit/UIKit.h>
#import <sqlite3.h>

@implementation MBTilesOverlay {
    sqlite3 *_db;
    sqlite3_stmt *_lookup;
    dispatch_queue_t _queue;      // serializes all sqlite use
}

- (instancetype)initWithPath:(NSString *)path {
    if ((self = [super initWithURLTemplate:nil])) {
        _queue = dispatch_queue_create("mbtiles", DISPATCH_QUEUE_SERIAL);
        if (sqlite3_open_v2(path.UTF8String, &_db,
                            SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
            NSLog(@"MBTiles open failed for %@: %s", path, sqlite3_errmsg(_db));
            sqlite3_close(_db);
            _db = NULL;
        }
        _storedMaxZoom = 14;
        if (_db) {
            sqlite3_prepare_v2(_db,
                "SELECT tile_data FROM tiles WHERE zoom_level = ? "
                "AND tile_column = ? AND tile_row = ?", -1, &_lookup, NULL);
            sqlite3_stmt *mz = NULL;
            sqlite3_prepare_v2(_db, "SELECT MAX(zoom_level) FROM tiles",
                               -1, &mz, NULL);
            if (mz && sqlite3_step(mz) == SQLITE_ROW)
                _storedMaxZoom = sqlite3_column_int(mz, 0);
            sqlite3_finalize(mz);
        }
        self.canReplaceMapContent = YES;
        self.minimumZ = 0;
        // Cover every zoom MapKit can reach: past the stored maximum the
        // overzoom serves (increasingly soft) crops. If this overlay ever
        // declined a zoom level, MapKit would draw its own online map there
        // instead - false comfort for an offline tool.
        self.maximumZ = 22;
        self.tileSize = CGSizeMake(256, 256);
    }
    return self;
}

- (void)dealloc {
    sqlite3_finalize(_lookup);
    sqlite3_close(_db);
}

// Runs on _queue. Returns stored bytes for (z, x, y), or nil.
- (NSData *)storedTileZ:(NSInteger)z x:(NSInteger)x y:(NSInteger)y {
    if (!_lookup) return nil;
    NSData *data = nil;
    sqlite3_reset(_lookup);
    sqlite3_bind_int64(_lookup, 1, z);
    sqlite3_bind_int64(_lookup, 2, x);
    sqlite3_bind_int64(_lookup, 3, ((1ll << z) - 1) - y);   // XYZ -> TMS row
    if (sqlite3_step(_lookup) == SQLITE_ROW)
        data = [NSData dataWithBytes:sqlite3_column_blob(_lookup, 0)
                              length:sqlite3_column_bytes(_lookup, 0)];
    return data;
}

// Crop-scale the deepest stored ancestor so zooming past the archive stays
// readable instead of going blank.
- (NSData *)overzoomTileZ:(NSInteger)z x:(NSInteger)x y:(NSInteger)y {
    NSInteger back = z - self.storedMaxZoom;
    NSInteger f = 1 << back;
    NSData *parent = [self storedTileZ:self.storedMaxZoom x:x / f y:y / f];
    if (!parent) return nil;
    UIImage *img = [UIImage imageWithData:parent];
    if (!img) return nil;

    CGFloat sub = 256.0 / f;
    CGRect crop = CGRectMake((x % f) * sub, (y % f) * sub, sub, sub);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(256, 256), YES, 1);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
    // Draw the parent scaled up so `crop` fills the 256pt canvas.
    [img drawInRect:CGRectMake(-crop.origin.x * f, -crop.origin.y * f,
                               256 * f, 256 * f)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return UIImageJPEGRepresentation(out, 0.8);
}

- (void)loadTileAtPath:(MKTileOverlayPath)path
                result:(void (^)(NSData *, NSError *))result {
    dispatch_async(_queue, ^{
        NSData *data = path.z <= self.storedMaxZoom
            ? [self storedTileZ:path.z x:path.x y:path.y]
            : [self overzoomTileZ:path.z x:path.x y:path.y];
        result(data, data ? nil : [NSError errorWithDomain:@"mbtiles"
                                                      code:404 userInfo:nil]);
    });
}

@end
