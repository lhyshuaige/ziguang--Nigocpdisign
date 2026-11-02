#ifndef NIGO_CORE_PORTME_H
#define NIGO_CORE_PORTME_H
#include <stddef.h>
#define HAS_FLOAT 0
#define HAS_TIME_H 0
#define HAS_STDIO 0
#define HAS_PRINTF 0
#define SEED_METHOD SEED_VOLATILE
#define MEM_METHOD MEM_STACK
#define MULTITHREAD 1
#define MAIN_HAS_NOARGC 1
#define MAIN_HAS_NORETURN 0
#define MEM_LOCATION "STACK in modeled DDR; I/D caches enabled"
#define COMPILER_VERSION "GCC " __VERSION__
#define COMPILER_FLAGS FLAGS_STR
typedef signed short ee_s16;
typedef unsigned short ee_u16;
typedef signed int ee_s32;
typedef unsigned int ee_u32;
typedef unsigned char ee_u8;
typedef double ee_f32;
typedef unsigned long ee_ptr_int;
typedef size_t ee_size_t;
typedef unsigned int CORE_TICKS;
#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x)-1) & ~3UL))
extern ee_u32 default_num_contexts;
typedef struct { ee_u8 portable_id; } core_portable;
void portable_init(core_portable *, int *, char *[]);
void portable_fini(core_portable *);
int ee_printf(const char *, ...);
#endif
