// Pure-C geodesy: WGS84 -> UTM -> MGRS, DMS formatting, bearings.
// No dependencies beyond libm so the same code runs on the phone (armv7)
// and natively on the build Mac for unit testing (make test).
#ifndef GEO_H
#define GEO_H

#include <stdbool.h>

typedef struct {
    int zone;            // 1..60
    char band;           // C..X latitude band (no I/O)
    double easting;      // meters, includes 500 km false easting
    double northing;     // meters, includes 10000 km false northing if south
    bool south;
} UTM;

// Convert WGS84 degrees to UTM, applying the Norway (32V) and Svalbard
// (31X/33X/35X/37X) zone exceptions. Valid for latitudes -80..84.
UTM geo_to_utm(double lat_deg, double lon_deg);

// Canonical compact MGRS at 1 m precision (truncated, per the spec),
// e.g. "16SEA6579382518". out must hold >= 16 bytes.
void geo_to_mgrs(double lat_deg, double lon_deg, char out[16]);

// Inverse UTM (band is ignored; zone/easting/northing/south drive it).
void utm_to_geo(UTM u, double *lat_deg, double *lon_deg);

// Parse compact uppercase MGRS ("16SEA6579382518", 1-15 chars, 0-10 digits)
// to the WGS84 coordinates of the grid square's SW corner. Returns false on
// any malformed input. Callers strip spaces and uppercase first.
bool geo_from_mgrs(const char *mgrs, double *lat_deg, double *lon_deg);

// One coordinate as degrees-minutes-seconds, e.g. 32°22'39.8"N.
// out must hold >= 20 bytes.
void geo_format_dms(double deg, bool is_lat, char out[20]);

// Initial great-circle bearing from point 1 to point 2, degrees [0, 360).
double geo_initial_bearing(double lat1, double lon1, double lat2, double lon2);

#endif
