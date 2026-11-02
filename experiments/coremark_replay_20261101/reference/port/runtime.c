/* Minimal console/runtime used outside the timed CoreMark algorithms. */
#include <stdarg.h>
#include <stddef.h>
static void putchar_mmio(char ch) { *(volatile unsigned *)0x10000000UL=(unsigned char)ch; }
static void number(unsigned value, unsigned base, unsigned width, char pad) {
    char buf[32];unsigned count=0;
    do {buf[count++]="0123456789abcdef"[value%base];value/=base;} while(value);
    while(width>count) {putchar_mmio(pad);--width;}
    while(count) putchar_mmio(buf[--count]);
}
int ee_printf(const char *fmt, ...) {
    va_list args;va_start(args,fmt);
    while(*fmt) {
        if(*fmt!='%') {putchar_mmio(*fmt++);continue;}
        ++fmt;char pad=' ';unsigned width=0;
        if(*fmt=='0') {pad='0';++fmt;}
        while(*fmt>='0'&&*fmt<='9') width=width*10+(*fmt++-'0');
        if(*fmt=='l') ++fmt; /* ILP32: int and long are both 32 bits. */
        char kind=*fmt++;
        if(kind=='s') {const char *s=va_arg(args,const char *);while(*s) putchar_mmio(*s++);}
        else if(kind=='c') putchar_mmio((char)va_arg(args,int));
        else if(kind=='d') {int n=va_arg(args,int);unsigned u=(unsigned)n;if(n<0){putchar_mmio('-');u=0u-u;}number(u,10,width,pad);}
        else if(kind=='u') number(va_arg(args,unsigned),10,width,pad);
        else if(kind=='x'||kind=='p') number(va_arg(args,unsigned),16,width,pad);
        else if(kind=='%') putchar_mmio('%');
    }
    va_end(args);return 0;
}
void *memcpy(void *dst,const void *src,size_t count) {char *d=dst;const char *s=src;while(count--) *d++=*s++;return dst;}
void *memset(void *dst,int val,size_t count) {unsigned char *d=dst;while(count--) *d++=(unsigned char)val;return dst;}
