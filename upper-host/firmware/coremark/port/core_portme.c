#include "coremark.h"
#include "benchmark.h"
#include <stdarg.h>
#ifdef CM_HOST_TEST
#include <time.h>
#endif

volatile ee_s32 seed1_volatile,seed2_volatile,seed3_volatile=0x66;
volatile ee_s32 seed4_volatile,seed5_volatile;
ee_u32 default_num_contexts=1;
char cm_log[CM_LOG_CAP];
uint32_t cm_log_length,cm_log_overflow;
uint64_t cm_ticks[2];
static uint64_t started,stopped;

uint64_t cm_read_ticks(void) {
#ifdef CM_HOST_TEST
    struct timespec now;clock_gettime(CLOCK_MONOTONIC,&now);
    return (uint64_t)now.tv_sec*CM_TIMER_HZ+(uint64_t)now.tv_nsec/10;
#else
    volatile uint32_t *timer=(volatile uint32_t *)(uintptr_t)0x10000000u;
    uint32_t hi,lo,next;
    do {
        hi=timer[3];__asm__ volatile("fence iorw,iorw" ::: "memory");
        lo=timer[2];__asm__ volatile("fence iorw,iorw" ::: "memory");
        next=timer[3];__asm__ volatile("fence iorw,iorw" ::: "memory");
    } while(hi!=next);
    return ((uint64_t)hi<<32)|lo;
#endif
}
void start_time(void){started=cm_read_ticks();}
void stop_time(void){stopped=cm_read_ticks();}
/* CoreMark's printed ticks are microseconds; raw 100 MHz ticks also returned. */
CORE_TICKS get_time(void){return (stopped-started)/100;}
secs_ret time_in_secs(CORE_TICKS ticks){return (double)ticks/1000000.0;}
void portable_init(core_portable *p,int *argc,char *argv[]) {
    (void)argc;(void)argv;
    if(sizeof(ee_ptr_int)!=sizeof(void *) || sizeof(ee_u32)!=4)
        ee_printf("ERROR! Invalid CoreMark port data types\n");
    p->portable_id=1;
}
void portable_fini(core_portable *p){p->portable_id=0;}

static void append(char c) {
    if(cm_log_length<CM_LOG_CAP-1)cm_log[cm_log_length++]=c;
    else cm_log_overflow=1;
    cm_log[cm_log_length]=0;
}
static void text(const char *s){while(*s)append(*s++);}
static void number(uint64_t value,unsigned base,unsigned width,char fill) {
    char tmp[32];unsigned n=0;
    do {tmp[n++]="0123456789abcdef"[value%base];value/=base;} while(value);
    while(width>n){append(fill);--width;}
    while(n)append(tmp[--n]);
}
/* Bounded logger for the formats used by unmodified CoreMark; no network I/O. */
int ee_printf(const char *format,...) {
    uint32_t before=cm_log_length;va_list args;va_start(args,format);
    while(*format) {
        if(*format!='%'){append(*format++);continue;}
        ++format;unsigned width=0;char fill=' ';int islong=0;
        if(*format=='0'){fill='0';++format;}
        while(*format>='0'&&*format<='9'){width=width*10+(unsigned)(*format++-'0');}
        if(*format=='l'){islong=1;++format;}
        char code=*format;if(code)++format;
        if(code=='s'){const char *s=va_arg(args,const char *);text(s?s:"(null)");}
        else if(code=='f') {
            double value=va_arg(args,double);
            if(value<0){append('-');value=-value;}
            uint64_t scaled=(uint64_t)(value*1000000.0+0.5);
            number(scaled/1000000,10,0,' ');append('.');number(scaled%1000000,10,6,'0');
        } else if(code=='d'||code=='i') {
            int64_t value=islong?va_arg(args,long):va_arg(args,int);
            if(value<0){append('-');value=-value;}
            number((uint64_t)value,10,width,fill);
        } else if(code=='u'||code=='x') {
            uint64_t value=islong?va_arg(args,unsigned long):va_arg(args,unsigned int);
            number(value,code=='x'?16:10,width,fill);
        } else if(code=='c')append((char)va_arg(args,int));
        else if(code=='%')append('%');
        else {text("[UNSUPPORTED FORMAT]");cm_log_overflow=1;}
    }
    va_end(args);return (int)(cm_log_length-before);
}

extern int coremark_main(void);
void cm_run(uint32_t iterations) {
    cm_log_length=0;cm_log_overflow=0;cm_log[0]=0;
    for(unsigned test=0;test<2;test++) {
        seed1_volatile=test?0x3415:0;seed2_volatile=seed1_volatile;
        seed3_volatile=0x66;seed4_volatile=(ee_s32)iterations;seed5_volatile=0;
        ee_printf(test?"=== VALIDATION ===\n":"=== PERFORMANCE ===\n");
#ifndef CM_HOST_TEST
        *(volatile uint32_t *)(uintptr_t)0x10000000u=2u<<test;
#endif
        (void)coremark_main();
        cm_ticks[test]=stopped-started;
    }
}
