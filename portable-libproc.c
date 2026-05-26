/*
 * portable-libproc.c — drop-in replacements for the libproc2 symbols that
 * `uptime` and `tload` call, for targets where /proc isn't available.
 *
 * Active on darwin and cosmo (Windows). On Linux the canonical
 * libproc2.a is linked instead and this file is not compiled.
 *
 * procps_uptime_snprint and the snprint_uptime_only helper are ported
 * verbatim from procps-ng-4.0.6 library/uptime.c (LGPL-2.1-or-later);
 * see source for original copyright. Adapted only to remove the
 * libproc2 PROCPS_EXPORT macro and the thread-local buffer helpers.
 */

#include <errno.h>
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <sys/types.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <utmpx.h>
#endif

/* prototypes (mirror library/include/misc.h) */
int procps_loadavg(double *av1, double *av5, double *av15);
int procps_uptime(double *uptime_secs, double *idle_secs);
int procps_users(void);
int procps_uptime_snprint(char *str, size_t size, double uptime_secs, int pretty);
int procps_container_uptime(double *uptime_secs);

int procps_loadavg(double *av1, double *av5, double *av15)
{
    double avg[3] = { 0.0, 0.0, 0.0 };
    int n = getloadavg(avg, 3);
    if (n < 0)
        return -1;
    if (av1)  *av1  = avg[0];
    if (av5)  *av5  = avg[1];
    if (av15) *av15 = avg[2];
    return 0;
}

int procps_uptime(double *uptime_secs, double *idle_secs)
{
    if (idle_secs) *idle_secs = 0.0;

#if defined(__APPLE__)
    struct timeval boot;
    size_t len = sizeof(boot);
    int mib[2] = { CTL_KERN, KERN_BOOTTIME };
    if (sysctl(mib, 2, &boot, &len, NULL, 0) != 0)
        return -errno;
    struct timeval now;
    if (gettimeofday(&now, NULL) != 0)
        return -errno;
    double secs = (double)(now.tv_sec - boot.tv_sec)
                + (double)(now.tv_usec - boot.tv_usec) / 1.0e6;
    if (uptime_secs) *uptime_secs = secs;
    return 0;
#else
    /* Cosmo/Windows path: CLOCK_BOOTTIME maps to GetTickCount64. */
    struct timespec ts;
#ifdef CLOCK_BOOTTIME
    if (clock_gettime(CLOCK_BOOTTIME, &ts) == 0) {
        if (uptime_secs) *uptime_secs = (double)ts.tv_sec + (double)ts.tv_nsec / 1.0e9;
        return 0;
    }
#endif
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
        return -errno;
    if (uptime_secs) *uptime_secs = (double)ts.tv_sec + (double)ts.tv_nsec / 1.0e9;
    return 0;
#endif
}

int procps_container_uptime(double *uptime_secs)
{
    /* Linux cgroup-aware variant has no analogue on darwin/cosmo;
       report system uptime. */
    return procps_uptime(uptime_secs, NULL);
}

int procps_users(void)
{
#if defined(__APPLE__)
    int n = 0;
    struct utmpx *u;
    setutxent();
    while ((u = getutxent()) != NULL) {
        if (u->ut_type == USER_PROCESS && u->ut_user[0] != '\0')
            n++;
    }
    endutxent();
    return n;
#else
    /* Cosmo/Windows: no utmp facility. Reported as 0; uptime renders
       "0 users" which is honest. */
    return 0;
#endif
}

/* ---- formatter (ported from library/uptime.c) ---- */

#define SECS_IN_DECADE 315360000
#define SECS_IN_YEAR    31536000
#define SECS_IN_WEEK      604800
#define SECS_IN_DAY        86400

static int snprint_uptime_only(char *restrict str, size_t size,
                               double uptime_secs, const int pretty)
{
#define print_this(VAL, UNITS) \
    if ( (l = snprintf(str + pos, size-pos, "%s%d %s", comma > 0 ? ", " : "", (VAL), (UNITS))) >= size) \
        return size; \
    else pos +=l
    size_t l;
    int pos = 0;
    int updecades = 0, upyears = 0, upweeks = 0, updays = 0, uphours = 0, upminutes = 0;
    int comma = 0;

    if (pretty) {
        if (uptime_secs > SECS_IN_DECADE) {
            updecades = (int) uptime_secs / SECS_IN_DECADE;
            uptime_secs -= updecades * SECS_IN_DECADE;
        }
        if (uptime_secs > SECS_IN_YEAR) {
            upyears = (int) uptime_secs / SECS_IN_YEAR;
            uptime_secs -= upyears * SECS_IN_YEAR;
        }
        if (uptime_secs > SECS_IN_WEEK) {
            upweeks = (int) uptime_secs / SECS_IN_WEEK;
            uptime_secs -= upweeks * SECS_IN_WEEK;
        }
    }
    if (uptime_secs > SECS_IN_DAY) {
        updays = (int) uptime_secs / SECS_IN_DAY;
        uptime_secs -= updays * SECS_IN_DAY;
    }
    if (uptime_secs > 60 * 60) {
        uphours = (int) uptime_secs / (60 * 60);
        uptime_secs -= uphours * 60 * 60;
    }
    if (uptime_secs > 60) {
        upminutes = (int) uptime_secs / 60;
        uptime_secs -= upminutes * 60;
    }

    if (pretty) {
        if (updecades) { print_this(updecades, updecades > 1 ? "decades" : "decade"); comma++; }
        if (upyears)   { print_this(upyears,   upyears > 1 ? "years" : "year");       comma++; }
        if (upweeks)   { print_this(upweeks,   upweeks > 1 ? "weeks" : "week");       comma++; }
    }
    if (updays) { print_this(updays, updays != 1 ? "days" : "day"); comma++; }

    if (pretty) {
        if (uphours)   { print_this(uphours,   uphours > 1 ? "hours" : "hour");       comma++; }
        if (upminutes || (!upminutes && uptime_secs <= 60)) {
            print_this(upminutes, upminutes > 1 ? "minutes" : "minute");
            comma++;
        }
    } else {
        if (uphours) {
            if ((l = snprintf(str + pos, size - pos, "%s%2d:%02d",
                              comma > 0 ? ", " : "", uphours, upminutes)) >= size)
                return size;
            else pos += l;
        } else {
            print_this(upminutes, "min");
        }
    }
    return pos;
#undef print_this
}

int procps_uptime_snprint(char *restrict str, size_t size,
                          double uptime_secs, const int pretty)
{
    size_t l;
    int pos = 0;
    time_t realseconds;
    struct tm realtime;
    int users;
    double av1, av5, av15;

    if (str == NULL)
        return -EINVAL;
    str[0] = '\0';

    if (time(&realseconds) < 0)
        return -errno;
    localtime_r(&realseconds, &realtime);

    if (pretty) {
        if ((l = snprintf(str + pos, size - pos, "%s", "up ")) >= size - pos)
            return size;
        pos += l;
    } else {
        if ((l = snprintf(str + pos, size - pos, " %02d:%02d:%02d up ",
                          realtime.tm_hour, realtime.tm_min, realtime.tm_sec)) >= size - pos)
            return size;
        pos += l;
    }
    l = snprint_uptime_only(str + pos, size - pos, uptime_secs, pretty);
    if (l >= size - pos)
        return size;
    if (l > 0)
        pos += l;

    if (pretty)
        return pos;

    users = procps_users();
    if (users < 0) {
        if ((l = snprintf(str + pos, size - pos, ", ? users,  ")) >= size - pos)
            return size;
        pos += l;
    } else {
        if ((l = snprintf(str + pos, size - pos, ", %2d %s,  ",
                          users, users != 1 ? "users" : "user")) >= size - pos)
            return size;
        pos += l;
    }

    procps_loadavg(&av1, &av5, &av15);
    if ((l = snprintf(str + pos, size - pos, "load average: %.2f, %.2f, %.2f",
                      av1, av5, av15)) >= size - pos)
        return size;
    pos += l;

    return pos;
}
