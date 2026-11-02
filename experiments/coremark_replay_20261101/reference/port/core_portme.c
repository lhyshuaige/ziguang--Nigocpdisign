/* Local bare-metal port. EEMBC timed algorithm files remain unmodified. */
#include "coremark.h"
#if VALIDATION_RUN
volatile ee_s32 seed1_volatile=0x3415, seed2_volatile=0x3415, seed3_volatile=0x66;
#else
volatile ee_s32 seed1_volatile=0, seed2_volatile=0, seed3_volatile=0x66;
#endif
volatile ee_s32 seed4_volatile=ITERATIONS, seed5_volatile=0;
ee_u32 default_num_contexts=1;
static CORE_TICKS begin_ticks, end_ticks;
static CORE_TICKS timer(void) { return *(volatile ee_u32 *)0x1001bff8UL; }
void start_time(void) { begin_ticks=timer(); }
void stop_time(void) { end_ticks=timer(); }
CORE_TICKS get_time(void) { return end_ticks-begin_ticks; }
secs_ret time_in_secs(CORE_TICKS ticks) { return ticks/100000000UL; }
void portable_init(core_portable *p, int *argc, char *argv[]) { (void)argc;(void)argv;p->portable_id=1; }
void portable_fini(core_portable *p) { p->portable_id=0;ee_printf("PORT_DONE\n"); }
