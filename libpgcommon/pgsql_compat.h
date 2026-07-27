#ifndef _PGSQL_COMPAT_H
#define _PGSQL_COMPAT_H 1

#include "access/tupdesc.h"
#include "postgres.h"

/* WHPG19 dropped Int8GetDatum()/DatumGetInt8() (the signed-8-bit accessor
 * pair) from postgres.h, keeping only the unsigned UInt8GetDatum()/
 * DatumGetUInt8(). flatgeobuf.c's flatgeobuf_column_type_byte case needs the
 * signed one to box a real `int8_t` value. Restore it as a local static
 * inline shim, matching upstream's own removed implementation.
 */
static inline Datum
Int8GetDatum(int8 X)
{
	return (Datum) X;
}

/* WHPG19: TupleDescAttr() is always a real `static inline` function here
 * (access/tupdesc.h), not a preprocessor macro, so `#ifndef TupleDescAttr`
 * always evaluated true and this shim's fallback -- direct access to a
 * `tupdesc->attrs[i]` field that no longer exists on TupleDescData -- was
 * silently shadowing the real function and breaking the build. This branch
 * only ever targets WHPG19, which always provides TupleDescAttr(), so the
 * pre-9.6.5 fallback is dropped rather than made conditional again.
 */

#endif /* _PGSQL_COMPAT_H */
