/**********************************************************************
 *
 * PostGIS - Spatial Types for PostgreSQL
 * http://postgis.net
 *
 * PostGIS is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * PostGIS is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with PostGIS.  If not, see <http://www.gnu.org/licenses/>.
 *
 **********************************************************************
 *
 * Copyright (C) 2011  OpenGeo.org
 *
 **********************************************************************/


#include "postgres.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "utils/elog.h"
#include "utils/guc.h"
#include "libpq/pqsignal.h"

#include "../postgis_config.h"

#include "lwgeom_log.h"
#include "lwgeom_pg.h"
#include "geos_c.h"

/*
 * This is required for builds against pgsql
 */
PG_MODULE_MAGIC;

/*
 * WHPG19: PostgreSQL widened its signal-handler signature (SIGNAL_ARGS now
 * carries an extra const pg_signal_info*, see c.h) and pqsignal() no longer
 * returns the previously-installed handler, so the old approach here of
 * installing a SIGINT handler and chaining to whatever was previously
 * registered (coreIntHandler) no longer compiles, and can't be made to work
 * the same way against the new API. Upstream PostGIS hit the identical
 * incompatibility against real PG18/19 and solved it by removing signal
 * handling entirely (postgis.net commit 1f7c3150b, "Rework interrupt
 * handling and remove signal handling from PostGIS. PostGIS does not need
 * to capture signals, it just needs to look at the state flags exposed by
 * PgSQL (QueryCancelPending || ProcDiePending) from time to time and
 * interrupt itself if they are set."), later simplified further by dropping
 * the ExecutorStart hook too (commit b72a2bb8a). This file ports that same
 * approach instead of reinventing signal-handler chaining against the new
 * WHPG19 ABI.
 */

static void interrupt_geos_callback()
{
#ifdef WIN32
	if (UNBLOCKED_SIGNAL_QUEUE())
	{
		pgwin32_dispatch_queued_signals();
	}
#endif
	/*
	 * If PgSQL global flags show interrupt,
	 * flip the pending flag in GEOS
	 * to end current query.
	 */
	if (QueryCancelPending || ProcDiePending)
	{
		GEOS_interruptRequest();
	}
}

static void interrupt_liblwgeom_callback()
{
#ifdef WIN32
	if (UNBLOCKED_SIGNAL_QUEUE())
	{
		pgwin32_dispatch_queued_signals();
	}
#endif
	/*
	 * If PgSQL global flags show interrupt,
	 * flip the pending flag in liblwgeom
	 * to end current query.
	 */
	if (QueryCancelPending || ProcDiePending)
	{
		lwgeom_request_interrupt();
	}
}

/*
* Pass proj error message out via the PostgreSQL logging
* system instead of letting them default into the
* stderr.
*/
#if POSTGIS_PROJ_VERSION > 60
#include "proj.h"

static void
pjLogFunction(void* data, int logLevel, const char* message)
{
	elog(DEBUG1, "libproj threw an exception (%d): %s", logLevel, message);
}
#endif

/*
 * Module load callback
 */
void _PG_init(void);
void
_PG_init(void)
{
	/*
	 * Hook up interrupt checking to call back here
	 * and examine the PgSQL interrupt state variables
	 */
	GEOS_interruptRegisterCallback(interrupt_geos_callback);
	lwgeom_register_interrupt_callback(interrupt_liblwgeom_callback);

	/* install PostgreSQL handlers */
	pg_install_lwgeom_handlers();

	/* pass proj messages through the pgsql error handler */
#if POSTGIS_PROJ_VERSION > 60
	proj_log_func(NULL, NULL, pjLogFunction);
#endif
}

/*
 * Module unload callback
 */
void _PG_fini(void);
void
_PG_fini(void)
{
	elog(NOTICE, "Goodbye from PostGIS %s", POSTGIS_VERSION);
}
