#import <MapKit/MapKit.h>

// Serves map tiles straight from an MBTiles (SQLite) file, fully offline,
// replacing Apple's base map. Zoom levels past the stored maximum are
// synthesized by crop-scaling the deepest stored tile (overzoom).
@interface MBTilesOverlay : MKTileOverlay
- (instancetype)initWithPath:(NSString *)path;
@property (nonatomic, readonly) NSInteger storedMaxZoom;
@end
