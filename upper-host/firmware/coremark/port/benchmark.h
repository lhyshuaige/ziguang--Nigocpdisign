#ifndef NIGO_BENCHMARK_H
#define NIGO_BENCHMARK_H
#include <stdint.h>
#define CM_LOG_CAP 8192u
#define CM_CPU_HZ 100000000u
#define CM_TIMER_HZ 100000000u
extern char cm_log[CM_LOG_CAP];
extern uint32_t cm_log_length,cm_log_overflow;
extern uint64_t cm_ticks[2];
uint64_t cm_read_ticks(void);
void cm_run(uint32_t iterations);
#endif
