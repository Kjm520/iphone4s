#include "Geo.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// WGS84 ellipsoid
static const double A = 6378137.0;
static const double F = 1.0 / 298.257223563;
static const double K0 = 0.9996;              // UTM scale on central meridian

static double rad(double deg) { return deg * M_PI / 180.0; }

static int utm_zone(double lat, double lon) {
    // Normalize just in case, then the standard 6-degree zones.
    while (lon >= 180.0) lon -= 360.0;
    while (lon < -180.0) lon += 360.0;
    int zone = (int)floor(lon / 6.0) + 31;
    // Norway: the V band widens zone 32 at Norway's southwest coast.
    if (lat >= 56.0 && lat < 64.0 && lon >= 3.0 && lon < 12.0) zone = 32;
    // Svalbard: bands X use zones 31/33/35/37 only.
    if (lat >= 72.0 && lat < 84.0) {
        if      (lon >= 0.0  && lon < 9.0)  zone = 31;
        else if (lon >= 9.0  && lon < 21.0) zone = 33;
        else if (lon >= 21.0 && lon < 33.0) zone = 35;
        else if (lon >= 33.0 && lon < 42.0) zone = 37;
    }
    return zone;
}

static char lat_band(double lat) {
    static const char bands[] = "CDEFGHJKLMNPQRSTUVWX"; // 8° each, -80..84
    int i = (int)floor((lat + 80.0) / 8.0);
    if (i < 0) i = 0;
    if (i > 19) i = 19;                        // X stretches to 84°
    return bands[i];
}

UTM geo_to_utm(double lat_deg, double lon_deg) {
    UTM u;
    u.zone = utm_zone(lat_deg, lon_deg);
    u.band = lat_band(lat_deg);
    u.south = lat_deg < 0.0;

    // Snyder, "Map Projections: A Working Manual", eqs. 8-9..8-13.
    double e2 = F * (2.0 - F);
    double e4 = e2 * e2, e6 = e4 * e2;
    double ep2 = e2 / (1.0 - e2);
    double phi = rad(lat_deg);
    double lam0 = rad(u.zone * 6.0 - 183.0);
    double sinp = sin(phi), cosp = cos(phi), tanp = tan(phi);

    double N = A / sqrt(1.0 - e2 * sinp * sinp);
    double T = tanp * tanp;
    double C = ep2 * cosp * cosp;
    double Am = cosp * (rad(lon_deg) - lam0);
    double M = A * ((1 - e2 / 4 - 3 * e4 / 64 - 5 * e6 / 256) * phi
                    - (3 * e2 / 8 + 3 * e4 / 32 + 45 * e6 / 1024) * sin(2 * phi)
                    + (15 * e4 / 256 + 45 * e6 / 1024) * sin(4 * phi)
                    - (35 * e6 / 3072) * sin(6 * phi));

    double A2 = Am * Am, A3 = A2 * Am, A4 = A2 * A2, A5 = A4 * Am, A6 = A4 * A2;
    u.easting = K0 * N * (Am + (1 - T + C) * A3 / 6
                          + (5 - 18 * T + T * T + 72 * C - 58 * ep2) * A5 / 120)
                + 500000.0;
    u.northing = K0 * (M + N * tanp * (A2 / 2
                       + (5 - T + 9 * C + 4 * C * C) * A4 / 24
                       + (61 - 58 * T + T * T + 600 * C - 330 * ep2) * A6 / 720));
    if (u.south) u.northing += 10000000.0;
    return u;
}

void geo_to_mgrs(double lat_deg, double lon_deg, char out[16]) {
    // 24 column letters (I and O excluded); zones cycle through three
    // 8-letter sets. 20 row letters; even zones offset the cycle by 5.
    static const char cols[] = "ABCDEFGHJKLMNPQRSTUVWXYZ";
    static const char rows[] = "ABCDEFGHJKLMNPQRSTUV";
    UTM u = geo_to_utm(lat_deg, lon_deg);

    int col = (int)(u.easting / 100000.0);            // 1..8 within zone
    char col_letter = cols[((u.zone - 1) % 3) * 8 + (col - 1)];
    int row = (int)(u.northing / 100000.0) % 20;
    if (u.zone % 2 == 0) row = (row + 5) % 20;
    char row_letter = rows[row];

    // MGRS truncates to the precision digits; it never rounds.
    int e5 = (int)fmod(u.easting, 100000.0);
    int n5 = (int)fmod(u.northing, 100000.0);
    snprintf(out, 16, "%02d%c%c%c%05d%05d",
             u.zone, u.band, col_letter, row_letter, e5, n5);
}

void utm_to_geo(UTM u, double *lat_deg, double *lon_deg) {
    // Snyder, "Map Projections: A Working Manual", eqs. 8-17..8-25.
    double e2 = F * (2.0 - F);
    double e4 = e2 * e2, e6 = e4 * e2;
    double ep2 = e2 / (1.0 - e2);

    double x = u.easting - 500000.0;
    double y = u.northing - (u.south ? 10000000.0 : 0.0);
    double mu = (y / K0) / (A * (1 - e2 / 4 - 3 * e4 / 64 - 5 * e6 / 256));
    double se = sqrt(1.0 - e2);
    double e1 = (1.0 - se) / (1.0 + se);
    double e12 = e1 * e1, e13 = e12 * e1, e14 = e12 * e12;
    double phi1 = mu + (3 * e1 / 2 - 27 * e13 / 32) * sin(2 * mu)
                     + (21 * e12 / 16 - 55 * e14 / 32) * sin(4 * mu)
                     + (151 * e13 / 96) * sin(6 * mu)
                     + (1097 * e14 / 512) * sin(8 * mu);

    double sp = sin(phi1), cp = cos(phi1), tp = tan(phi1);
    double C1 = ep2 * cp * cp;
    double T1 = tp * tp;
    double N1 = A / sqrt(1 - e2 * sp * sp);
    double R1 = A * (1 - e2) / pow(1 - e2 * sp * sp, 1.5);
    double D = x / (N1 * K0);
    double D2 = D * D, D3 = D2 * D, D4 = D2 * D2, D5 = D4 * D, D6 = D4 * D2;

    double phi = phi1 - (N1 * tp / R1) * (D2 / 2
                 - (5 + 3 * T1 + 10 * C1 - 4 * C1 * C1 - 9 * ep2) * D4 / 24
                 + (61 + 90 * T1 + 298 * C1 + 45 * T1 * T1
                    - 252 * ep2 - 3 * C1 * C1) * D6 / 720);
    double lam = (D - (1 + 2 * T1 + C1) * D3 / 6
                 + (5 - 2 * C1 + 28 * T1 - 3 * C1 * C1
                    + 8 * ep2 + 24 * T1 * T1) * D5 / 120) / cp;

    *lat_deg = phi * 180.0 / M_PI;
    *lon_deg = (u.zone * 6.0 - 183.0) + lam * 180.0 / M_PI;
}

// Index of c in set, or -1 (strchr with index semantics, which is what
// every caller here actually wants).
static int find_char(const char *set, char c) {
    for (int i = 0; set[i]; i++)
        if (set[i] == c) return i;
    return -1;
}

bool geo_from_mgrs(const char *s, double *lat_deg, double *lon_deg) {
    static const char cols[] = "ABCDEFGHJKLMNPQRSTUVWXYZ";
    static const char rows[] = "ABCDEFGHJKLMNPQRSTUV";
    static const char bands[] = "CDEFGHJKLMNPQRSTUVWX";
    size_t n = strlen(s);
    if (n < 5 || n > 15) return false;

    size_t i = 0;
    int zone = 0;
    while (i < 2 && s[i] >= '0' && s[i] <= '9') zone = zone * 10 + (s[i++] - '0');
    if (i == 0 || zone < 1 || zone > 60) return false;

    int band_idx = find_char(bands, s[i++]);
    if (band_idx < 0) return false;
    int col = find_char(cols, s[i++]) - ((zone - 1) % 3) * 8;  // 0..7 in set
    if (col < 0 || col > 7) return false;
    int row = find_char(rows, s[i++]);
    if (row < 0) return false;
    if (zone % 2 == 0) row = (row - 5 + 20) % 20;      // undo even-zone offset

    size_t nd = n - i;
    if (nd % 2 || nd > 10) return false;
    size_t half = nd / 2;
    double scale = pow(10.0, 5.0 - (double)half);
    long ev = 0, nv = 0;
    for (size_t k = 0; k < half; k++) {
        char ce = s[i + k], cn = s[i + half + k];
        if (ce < '0' || ce > '9' || cn < '0' || cn > '9') return false;
        ev = ev * 10 + (ce - '0');
        nv = nv * 10 + (cn - '0');
    }

    double easting = (col + 1) * 100000.0 + ev * scale;
    double n_base = row * 100000.0 + nv * scale;       // 0 .. 2,000,000
    bool south = band_idx <= 9;                        // bands C..M
    double band_min = -80.0 + band_idx * 8.0;
    double band_max = band_idx == 19 ? 84.0 : band_min + 8.0;

    // Row letters repeat every 2000 km; the latitude band disambiguates.
    for (int k = 0; k < 5; k++) {
        double cand = n_base + k * 2000000.0;
        if (cand >= 10000000.0) break;
        UTM u = { .zone = zone, .band = bands[band_idx],
                  .easting = easting, .northing = cand, .south = south };
        double la, lo;
        utm_to_geo(u, &la, &lo);
        if (la >= band_min - 0.5 && la <= band_max + 0.5) {
            *lat_deg = la;
            *lon_deg = lo;
            return true;
        }
    }
    return false;
}

void geo_format_dms(double deg, bool is_lat, char out[20]) {
    char hemi = deg >= 0 ? (is_lat ? 'N' : 'E') : (is_lat ? 'S' : 'W');
    double a = fabs(deg);
    int d = (int)a;
    double mf = (a - d) * 60.0;
    int m = (int)mf;
    double s = (mf - m) * 60.0;
    if (s >= 59.95) { s = 0.0; m += 1; }              // carry after rounding
    if (m == 60) { m = 0; d += 1; }
    snprintf(out, 20, "%d\xC2\xB0%02d'%04.1f\"%c", d, m, s, hemi);
}

double geo_initial_bearing(double lat1, double lon1, double lat2, double lon2) {
    double p1 = rad(lat1), p2 = rad(lat2), dl = rad(lon2 - lon1);
    double y = sin(dl) * cos(p2);
    double x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl);
    double b = atan2(y, x) * 180.0 / M_PI;
    return fmod(b + 360.0, 360.0);
}
