// Host-side unit test for Geo.c - runs natively on the build Mac (make test).
// Reference values generated independently with PROJ (pyproj) for UTM and
// NGA GEOTRANS (python mgrs) for MGRS strings; see tools history in repo.
#include "Geo.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;

#define CHECK(cond, ...) do { \
    if (!(cond)) { failures++; printf("FAIL %s: ", vec.name); printf(__VA_ARGS__); printf("\n"); } \
} while (0)

struct vec {
    const char *name;
    double lat, lon;
    int zone;
    char band;
    double easting, northing;
    const char *mgrs;
};

static const struct vec VECTORS[] = {
    {"equator/prime meridian", 0.0, 0.0, 31, 'N', 166021.443, 0.000, "31NAA6602100000"},
    {"Montgomery AL capitol", 32.377716, -86.300568, 16, 'S', 565793.524, 3582518.966, "16SEA6579382518"},
    {"Huntsville AL", 34.730369, -86.586104, 16, 'S', 537892.285, 3843220.651, "16SED3789243220"},
    {"White House", 38.8977, -77.0365, 18, 'S', 323394.296, 4307395.634, "18SUJ2339407395"},
    {"Sydney Opera House", -33.8568, 151.2153, 56, 'H', 334900.570, 6252288.753, "56HLH3490052288"},
    {"Bergen Norway (32V exception)", 60.393, 5.324, 32, 'V', 297469.111, 6700831.637, "32VKN9746900831"},
    {"Svalbard (33X exception)", 78.22, 15.65, 33, 'X', 514813.527, 8683004.153, "33XWG1481383004"},
    {"Patagonia", -45.5734, -72.0682, 18, 'G', 728752.474, 4949167.491, "18GYQ2875249167"},
    {"Anchorage AK", 61.2166, -149.8944, 6, 'V', 344556.506, 6790355.855, "06VUN4455690355"},
    {"band boundary 56N", 56.1, 8.5, 32, 'V', 468896.810, 6217322.052, "32VMH6889617322"},
};

int main(void) {
    for (unsigned i = 0; i < sizeof(VECTORS) / sizeof(*VECTORS); i++) {
        struct vec vec = VECTORS[i];
        UTM u = geo_to_utm(vec.lat, vec.lon);
        CHECK(u.zone == vec.zone, "zone %d != %d", u.zone, vec.zone);
        CHECK(u.band == vec.band, "band %c != %c", u.band, vec.band);
        CHECK(fabs(u.easting - vec.easting) < 0.05,
              "easting %.3f != %.3f", u.easting, vec.easting);
        CHECK(fabs(u.northing - vec.northing) < 0.05,
              "northing %.3f != %.3f", u.northing, vec.northing);
        char mgrs[16];
        geo_to_mgrs(vec.lat, vec.lon, mgrs);
        CHECK(strcmp(mgrs, vec.mgrs) == 0, "mgrs %s != %s", mgrs, vec.mgrs);
    }

    {
        struct vec vec = {.name = "dms formatting"};
        char s[20];
        geo_format_dms(32.377716, true, s);
        CHECK(strcmp(s, "32\xC2\xB0" "22'39.8\"N") == 0, "lat dms got %s", s);
        geo_format_dms(-86.300568, false, s);
        CHECK(strcmp(s, "86\xC2\xB0" "18'02.0\"W") == 0, "lon dms got %s", s);
        geo_format_dms(9.9999999, true, s);   // rounding must carry cleanly
        CHECK(strcmp(s, "10\xC2\xB0" "00'00.0\"N") == 0, "carry dms got %s", s);
    }

    {
        struct vec vec = {.name = "bearings"};
        CHECK(fabs(geo_initial_bearing(0, 0, 0, 10) - 90.0) < 1e-9, "east");
        CHECK(fabs(geo_initial_bearing(0, 0, 10, 0) - 0.0) < 1e-9, "north");
        CHECK(fabs(geo_initial_bearing(10, 0, 0, 0) - 180.0) < 1e-9, "south");
        CHECK(fabs(geo_initial_bearing(0, 0, -1, -1) - 225.0) < 0.01, "southwest");
    }

    // Forward -> inverse round trip must land back on the same spot.
    for (unsigned i = 0; i < sizeof(VECTORS) / sizeof(*VECTORS); i++) {
        struct vec vec = VECTORS[i];
        double la, lo;
        utm_to_geo(geo_to_utm(vec.lat, vec.lon), &la, &lo);
        CHECK(fabs(la - vec.lat) < 2e-6 && fabs(lo - vec.lon) < 2e-6,
              "round trip %.8f,%.8f != %.8f,%.8f", la, lo, vec.lat, vec.lon);
    }

    // MGRS parsing against GEOTRANS (SW corner of the named square).
    {
        static const struct { const char *mgrs; double lat, lon; } INV[] = {
            {"31NAA6602100000", 0.00000000, -0.00000398},
            {"16SEA6579382518", 32.37770731, -86.30057363},
            {"16SED3789243220", 34.73036314, -86.58610714},
            {"18SUJ2339407395", 38.89769423, -77.03650325},
            {"56HLH3490052288", -33.85680670, 151.21529370},
            {"32VKN9746900831", 60.39299424, 5.32399864},
            {"33XWG1481383004", 78.21999868, 15.64997679},
            {"18GYQ2875249167", -45.57340457, -72.06820584},
            {"06VUN4455690355", 61.21659213, -149.89440871},
            {"16SEA65798251", 32.37763533, -86.30060608},   // 10 m form
            {"16SEA657825", 32.37755042, -86.30156348},     // 100 m form
        };
        for (unsigned i = 0; i < sizeof(INV) / sizeof(*INV); i++) {
            struct vec vec = {.name = INV[i].mgrs};
            double la, lo;
            CHECK(geo_from_mgrs(INV[i].mgrs, &la, &lo), "parse rejected");
            CHECK(fabs(la - INV[i].lat) < 1e-6 && fabs(lo - INV[i].lon) < 1e-6,
                  "got %.8f,%.8f want %.8f,%.8f", la, lo, INV[i].lat, INV[i].lon);
        }
    }

    // Malformed MGRS must be rejected, never misread.
    {
        struct vec vec = {.name = "mgrs rejects"};
        static const char *BAD[] = {
            "", "16", "16S", "16SEA657",                   // odd digit count
            "16IEA6579382518",                             // I is no band
            "16SIA6579382518",                             // I is no column
            "16SEO6579382518",                             // O is no row
            "16SZA6579382518",                             // col not in zone's set
            "99SEA6579382518",                             // zone > 60
            "16SEA65793825189",                            // 11 digits
            "16SEA6579382518X",                            // trailing junk
        };
        for (unsigned i = 0; i < sizeof(BAD) / sizeof(*BAD); i++) {
            double la, lo;
            CHECK(!geo_from_mgrs(BAD[i], &la, &lo), "accepted \"%s\"", BAD[i]);
        }
    }

    if (failures) {
        printf("geo_test: %d FAILURE(S)\n", failures);
        return 1;
    }
    printf("geo_test: all passed\n");
    return 0;
}
